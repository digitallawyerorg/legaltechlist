require "test_helper"

class LegaltechAtlasTest < ActiveSupport::TestCase
  test "slug_for normalizes company names to atlas slugs" do
    assert_equal "clio", LegaltechAtlas.slug_for("Clio")
    assert_equal "kira-systems", LegaltechAtlas.slug_for("Kira Systems")
    assert_equal "blue-j-legal", LegaltechAtlas.slug_for("Blue J Legal")
    assert_equal "thomson-reuters", LegaltechAtlas.slug_for("Thomson Reuters")
  end

  test "company_url builds canonical atlas profile urls" do
    assert_equal "https://legaltechatlas.com/companies/clio", LegaltechAtlas.company_url("clio")
  end

  test "parse_company_urls_from_sitemap indexes slugs" do
    xml = <<~XML
      <urlset>
        <url><loc>https://legaltechatlas.com/companies/clio</loc></url>
        <url><loc>https://legaltechatlas.com/companies/harvey</loc></url>
      </urlset>
    XML

    urls = LegaltechAtlas.parse_company_urls_from_sitemap(xml)
    assert_equal "https://legaltechatlas.com/companies/clio", urls["clio"]
    assert_equal "https://legaltechatlas.com/companies/harvey", urls["harvey"]
  end
end
