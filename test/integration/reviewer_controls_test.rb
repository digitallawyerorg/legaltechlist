require "test_helper"

# The same decision offered in two places has to be the same decision. These cover the
# duplicated reviewer controls on the company record — one set in the header's More
# menu, one in the Reviewer decision section at the foot of the page — and the
# confirmation the markup has always claimed to carry.
class ReviewerControlsTest < ActionDispatch::IntegrationTest
  include Devise::Test::IntegrationHelpers

  setup do
    sign_in admin_users(:one)
    @company = companies(:one)
    @company.update_columns(quality_status: nil, visible: true)
  end

  def show!
    get custom_admin_company_review_path(@company.id)
    assert_response :success
  end

  # ---- one action, two places ---------------------------------------------

  test "both Needs more work controls post the same decision to the same handler" do
    show!

    assert_select "form[action=?]", custom_admin_company_mark_review_path(@company.id) do
      assert_select "input[name=decision][value=needs_work]", { count: 2 },
                    "the More menu and the Reviewer decision section should be two routes to one action"
    end
  end

  test "both Reject and hide controls post the same decision and both ask first" do
    show!

    assert_select "input[name=decision][value=reject]", count: 2
    assert_select "form[data-turbo-confirm*=?]", "Reject and hide", { count: 2 },
                  "a destructive action has to be confirmed from either entry point"
  end

  test "both Return to contributor controls open the one form, and only one exists" do
    show!

    assert_select "[data-bs-toggle=collapse][data-bs-target='#returnToContributorPanel']", count: 2
    assert_select "#returnToContributorPanel form", { count: 1 },
                  "two controls opening two copies of a form is how half-typed instructions get lost"
    assert_select "#returnToContributorPanel textarea[name=contributor_instructions][required]", { count: 1 },
                  "the field the reviewer has to fill in is the one focus should land on"
  end

  # The admin layout loads bootstrap and nothing else — no Turbo, no UJS — so for as
  # long as nothing listened for them the data-turbo-confirm attributes here were
  # decoration: "Delete this company. This permanently removes the record" fired on the
  # first click with no prompt. This asserts the handler is actually shipped.
  test "the admin ships something that acts on the confirmations it renders" do
    show!

    assert_select "form[data-turbo-confirm]", minimum: 1
    assert_match(/adminSubmitting/, @response.body,
                 "confirmation and double-submit protection come from this handler; without it the attributes are inert")
    assert_match(/window\.confirm/, @response.body)
  end

  # ---- a duplicate is legible on the record --------------------------------

  test "a duplicate is shown with its status, not as a bare name" do
    twin = Company.create!(
      name: @company.name, location: "Boston, MA", description: "Another entry for the same company.",
      category: categories(:one), target_client: target_clients(:one), business_models: [business_models(:one)],
      main_url: @company.main_url
    )
    twin.update_columns(visible: false)

    show!

    assert_select "a[href=?]", custom_admin_company_review_path(twin.id)
    assert_match(/Not public/, @response.body,
                 "a live public entry and an unpublished draft resolve in opposite directions")
    assert_match(/unresolved/, @response.body)
  end

  # ---- the reviewer keeps their place -------------------------------------

  QUEUE = { "review_state" => "not_reviewed", "category_id" => "1", "sort" => "readiness", "page" => "3" }.freeze

  test "a decision that leaves the reviewer on the record keeps the queue they came from" do
    post custom_admin_company_mark_review_path(@company.id), params: { decision: "needs_work", queue: QUEUE }

    assert_response :redirect
    target = @response.headers["Location"]
    assert_includes target, "/admin/review/companies/#{@company.id}"
    QUEUE.each { |key, value| assert_includes target, "queue%5B#{key}%5D=#{value}" }
  end

  test "a refused decision keeps both the record and the queue" do
    post custom_admin_company_mark_review_path(@company.id),
         params: { decision: "return_to_contributor", contributor_instructions: "", queue: QUEUE }

    assert_response :redirect
    assert_includes @response.headers["Location"], "/admin/review/companies/#{@company.id}"
    assert_includes @response.headers["Location"], "queue%5Breview_state%5D=not_reviewed"
    assert flash[:alert].present?, "the reviewer has to be told why nothing happened"
  end

  test "running an agent review from the record keeps the queue" do
    CompanyAgentReviewService.stub(:call, PipelineRun.create!(name: "stub", run_type: "agent_review", status: "succeeded")) do
      post custom_admin_company_agent_review_path(@company.id), params: { queue: QUEUE }
    end

    assert_response :redirect
    assert_includes @response.headers["Location"], "queue%5Bsort%5D=readiness"
  end

  # ---- the decision is reported honestly ----------------------------------

  test "a write that did not save is reported as a failure, not a success" do
    refuse = ->(**) { raise CompanyReviewMarkService::NotConfirmed.new(@company, { "quality_status" => { "requested" => "verified", "saved" => nil } }) }
    CompanyReviewMarkService.stub(:call, refuse) do
      post custom_admin_company_mark_review_path(@company.id), params: { decision: "verified" }
    end

    assert_response :redirect
    assert_nil flash[:notice], "reporting success for a write that did not land is the failure mode this guards"
    assert_match(/reported success, but the value was not saved/, flash[:alert].to_s)
  end
end
