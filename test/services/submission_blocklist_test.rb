require "test_helper"

class SubmissionBlocklistTest < ActiveSupport::TestCase
  test "seeded entries are loaded from the config file" do
    assert_includes SubmissionBlocklist.domains, "fxutwwaassxocp.com"
    assert_includes SubmissionBlocklist.domains, "snkzizjsygw.com"
    assert_includes SubmissionBlocklist.link_hosts, "brnd.li"
    assert_includes SubmissionBlocklist.link_hosts, "bynd.li"
    assert_includes SubmissionBlocklist.link_hosts, "qmy.li"
  end

  test "blocked submission domain matches with or without www and on subdomains" do
    assert_equal "fxutwwaassxocp.com", SubmissionBlocklist.blocked_domain_for("https://www.fxutwwaassxocp.com/")
    assert_equal "snkzizjsygw.com", SubmissionBlocklist.blocked_domain_for("http://snkzizjsygw.com")
    assert_equal "snkzizjsygw.com", SubmissionBlocklist.blocked_domain_for("https://go.pages.snkzizjsygw.com/offer")
  end

  test "blocked submission domain does not match a domain that merely ends in the same letters" do
    assert_nil SubmissionBlocklist.blocked_domain_for("https://notsnkzizjsygw.com")
    assert_nil SubmissionBlocklist.blocked_domain_for("https://lawyer.example.com")
    assert_nil SubmissionBlocklist.blocked_domain_for(nil)
  end

  test "blocked link host matches a space-mangled dot" do
    footer = "kindly fill the form at brnd .li/delist url with your domain address (URL)."

    assert_equal "brnd.li", SubmissionBlocklist.blocked_link_host_in(footer)
    assert_equal "brnd.li", SubmissionBlocklist.blocked_link_host_in("visit brnd . li/delist")
    assert_equal "brnd.li", SubmissionBlocklist.blocked_link_host_in("visit brnd (dot) li/delist")
    assert_equal "brnd.li", SubmissionBlocklist.blocked_link_host_in("visit brnd dot li/delist")
  end

  test "blocked link host matches a plain shortlink in any case" do
    assert_equal "bynd.li", SubmissionBlocklist.blocked_link_host_in("Restore your sites now: https://bynd.li/restorenow")
    assert_equal "qmy.li", SubmissionBlocklist.blocked_link_host_in("HTTPS://QMY.LI/CPUS")
  end

  test "blocked link host does not match a legitimate domain containing the entry" do
    assert_nil SubmissionBlocklist.blocked_link_host_in("We partner with notbrnd.link on intake.")
    assert_nil SubmissionBlocklist.blocked_link_host_in("See mybrnd.limited for details.")
    assert_nil SubmissionBlocklist.blocked_link_host_in("Contract review at brnd.limited and abrnd.li")
    assert_nil SubmissionBlocklist.blocked_link_host_in("Contract workflow software for in-house teams.")
    assert_nil SubmissionBlocklist.blocked_link_host_in(nil)
  end
end
