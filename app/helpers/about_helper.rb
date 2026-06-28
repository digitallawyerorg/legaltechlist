module AboutHelper
  CONTRIBUTORS = [
    { name: "Pieter Gunst", role: "CodeX Fellow / Co-Founder of Legal.io", linkedin: "pietergunst" },
    { name: "Kevin Xu", role: "Code = Law Participant", linkedin: "kevinsxu" },
    { name: "Sam Schroeder", role: "Code = Law Participant", linkedin: "sambchroeder" },
    { name: "Elizabeth Lowell", role: "Code = Law Participant", linkedin: "elizabeth-lowell-43393911" },
    { name: "Mark Evans", role: "CodeX Fellow", linkedin: "markharrisevans" },
    { name: "David Curle", role: "Thomson Reuters", linkedin: "david-curle-6a56" },
    { name: "Bob Ambrogi", role: "Lawyer, media and technology professional", linkedin: "robertambrogi" },
    { name: "Patrick Haede", role: "Intern at CodeX", linkedin: "patrickhaede" },
    { name: "Taylor Famighetti", role: "Intern at CodeX", linkedin: "taylor-famighetti-06456083" },
    { name: "Paul Blizzard", role: "Visiting Student Researcher at CodeX", linkedin: "paulblizzard" }
  ].freeze

  def about_contributors
    CONTRIBUTORS
  end

  def about_contributor_role(contributor)
    "Contributor, #{contributor[:role]}"
  end

  def about_linkedin_url(linkedin_slug)
    "https://www.linkedin.com/in/#{linkedin_slug}"
  end
end
