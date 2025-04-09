require 'csv'

class ImportCsvToCompanyService
  class << self

    def import(csv_data)
      stats = { created: 0, updated: 0, skipped: 0, errors: 0 }

      CSV.foreach(csv_data.tempfile, :headers => true, :encoding => 'UTF-8') do |raw_row|
        begin
          row = map_input_row(raw_row)
          name = row["name"].to_s.strip

          if name.blank?
            stats[:skipped] += 1
            next
          end

          # Clean up required fields
          business_model = raw_row["Business Model"] || raw_row["suggested_business_model"] || "Unknown"
          target_client = raw_row["target_client"] || raw_row["suggested_target_client"] || "Unknown"
          category = raw_row["Category"] || raw_row["suggested_category"] || "Unknown"

          # Get category and subcategory
          catName = category.to_s.split('-').first.to_s.strip
          catName = "Unknown" if catName.blank?
          subCatName = category.to_s.split('-')[1].to_s.strip

          # Create or find associated records
          cat = Category.where(:name => catName).first_or_create!
          sub = SubCategory.where(:name => subCatName, :category => cat).first_or_create! if subCatName.present?
          biz = BusinessModel.where(:name => business_model).first_or_create!
          trg = TargetClient.where(:name => target_client).first_or_create!

          # Find existing company
          company = Company.where("TRIM(name) = ?", name.strip).first

          # Parse exit date safely
          exit_date = begin
            row["Exit Date"].present? ? Date.parse(row["Exit Date"]) : nil
          rescue
            nil
          end

          # Determine funding status and stage
          funding_status = determine_funding_status(raw_row)

          # Build a comprehensive description
          description = row["description"].to_s.strip
          description = "No description available." if description.blank?

          # Get location, with fallbacks
          location = row["location"]
          if location.blank? && row["headquarters_region"].present?
            location = clean_location(row["headquarters_region"])
          end
          location ||= "Location unknown" # Final fallback

          attributes = {
            name: name,
            contact_name: raw_row["Contact Name"] || "Unknown",
            contact_email: row["contact_email"],
            location: location,
            founded_date: row["founded_date"],
            visible: true, # All imported companies are verified
            category: cat,
            sub_category: sub,
            target_client: trg,
            business_model: biz,
            description: description,
            main_url: row["main_url"],
            twitter_url: row["twitter_url"],
            linkedin_url: row["linkedin_url"],
            facebook_url: row["facebook_url"],
            status: row["status"],

            # Trend analysis fields
            total_funding_amount_usd: row["total_funding_amount_usd"],
            funding_status: funding_status,
            number_of_funding_rounds: row["number_of_funding_rounds"],
            exit_date: exit_date,
            founders: row["founders"],
            headquarters_region: row["headquarters_region"],

            # Skip geocoding during import
            skip_geocoding: true
          }

          if company
            if company.attributes.except('id', 'created_at', 'updated_at') != attributes
              company.assign_attributes(attributes)
              company.skip_geocoding = true
              company.save!
              company.all_tags = raw_row["suggested_tags"].to_s if raw_row["suggested_tags"].present?
              stats[:updated] += 1
            else
              stats[:skipped] += 1
            end
          else
            company = Company.new(attributes)
            company.skip_geocoding = true
            company.save!
            company.all_tags = raw_row["suggested_tags"].to_s if raw_row["suggested_tags"].present?
            stats[:created] += 1
          end
        rescue => e
          Rails.logger.error "Error importing row: #{raw_row.inspect}"
          Rails.logger.error e.message
          Rails.logger.error e.backtrace.join("\n")
          stats[:errors] += 1
        end
      end

      stats
    end

    def export(csv)

      # NOTE! The order of this list must match the order of the rows (below)
      header =  [
        "contact_name",
        "contact_email",
        "name",
        "location",
        "founded_date",
        "visible",
        "category",
        "target_client",
        "business_model",
        "description",
        "main_url",
        "twitter_url",
        "angellist_url",
        "crunchbase_url",
        "linkedin_url",
        "facebook_url",
        "legalio_url",
        "status",
        "all_tags",
        "codex_presenter",
        "codex_presentation_date"
      ]

      csv << header

      Company.all.each do |company|
        category = company.category.name

        if company.sub_category.present?
          category = "#{company.category.name} - #{company.sub_category.name}"
        end

        if company.target_client.present?
          trg = company.target_client.name
        end

        if company.business_model.present?
          biz = company.business_model.name
        end

        row = [
          company.contact_name,
          company.contact_email,
          company.name,
          company.location,
          company.founded_date,
          company.visible,
          category,
          trg,
          biz,
          company.description,
          company.main_url,
          company.twitter_url,
          company.angellist_url,
          company.crunchbase_url,
          company.linkedin_url,
          company.facebook_url,
          company.legalio_url,
          company.status,
          company.tags.any? ? company.all_tags : "",
          company.codex_presenter,
          company.codex_presentation_date
         ]

        csv << row
      end

    end

    private

    def clean_location(location)
      return nil if location.blank?

      # Extract city and country, removing special characters
      parts = location.split(',').map { |part| part.strip.gsub(/[^\p{L}\p{N}\s,]/, '') }
      return parts.first if parts.size == 1

      [parts.first, parts.last].join(', ')
    end

    def clean_date(date_string)
      return nil if date_string.blank?

      # Handle obviously wrong dates
      return nil if date_string.start_with?('15') # Exclude 1500s dates

      # Extract year
      if date_string.match?(/^\d{4}/)
        date_string[0..3] # Get just the year
      else
        begin
          Date.parse(date_string).year.to_s
        rescue
          nil
        end
      end
    end

    def clean_url(url)
      return nil if url.blank?

      # Ensure URL has protocol
      unless url.start_with?('http://', 'https://')
        url = "https://#{url}"
      end

      url
    end

    def normalize_company_name(name)
      return nil if name.blank?

      # Remove common suffixes and clean up
      name.gsub(/\b(llc|ltd|inc|corp|corporation|limited)\b/i, '')
          .gsub(/[^\w\s-]/, '') # Remove special characters
          .squeeze(' ')         # Remove multiple spaces
          .strip
    end

    def map_input_row(row)
      org_name = row['Organization Name'].to_s.strip
      org_name = org_name.gsub(/\b(llc|ltd|inc|corp|corporation|limited)\b/i, '').strip

      {
        'name' => org_name,
        'main_url' => clean_url(row['Website']),
        'location' => clean_location(row['Headquarters Location']),
        'founded_date' => clean_date(row['Founded Date']),
        'description' => row['Description'].to_s.strip,
        'twitter_url' => clean_url(row['Twitter']),
        'linkedin_url' => clean_url(row['LinkedIn']),
        'facebook_url' => clean_url(row['Facebook']),
        'status' => row['Operating Status'],
        'category' => row['Category'],
        'stage' => row['Stage'],
        'company_type' => row['Company Type'],
        'number_of_funding_rounds' => row['Number of Funding Rounds'].to_i,
        'total_funding_amount_usd' => clean_funding_amount(row),
        'funding_status' => row['Funding Status'],
        'founders' => row['Founders'],
        'contact_email' => row['Contact Email'],
        'headquarters_region' => row['Headquarters Location'],
        'suggested_tags' => row['suggested_tags'],

        # Preserve original values for reference
        'Organization Name' => row['Organization Name'],
        'Website' => row['Website'],
        'Headquarters Location' => row['Headquarters Location'],
        'Founded Date' => row['Founded Date'],
        'Description' => row['Description'],
        'Twitter' => row['Twitter'],
        'LinkedIn' => row['LinkedIn'],
        'Facebook' => row['Facebook'],
        'Operating Status' => row['Operating Status'],
        'Stage' => row['Stage'],
        'Company Type' => row['Company Type'],
        'Number of Funding Rounds' => row['Number of Funding Rounds'],
        'Total Funding Amount (in USD)' => row['Total Funding Amount (in USD)'],
        'Funding Status' => row['Funding Status'],
        'Founders' => row['Founders'],
        'Contact Email' => row['Contact Email']
      }
    end

    def valid_for_import?(row)
      return false if row['name'].blank?
      true
    end

    def determine_funding_status(row)
      # Check for exit events first
      return 'IPO' if row['Stage'].to_s.match?(/public/i) || row['Operating Status'].to_s.match?(/ipo|public/i)
      return 'M&A' if row['Stage'].to_s.match?(/acquired/i) || row['Operating Status'].to_s.match?(/acquired|merged/i) || row['Exit Date'].present?

      # Map funding stages
      stage = row['Stage'].to_s.strip.downcase
      case stage
      when /series a/
        'Early Stage Venture'
      when /series b/
        'Late Stage Venture'
      when /series c|series d|series e|series f/
        'Late Stage Venture'
      when /seed|angel/
        'Seed'
      when /private equity|growth equity/
        'Private Equity'
      when /early stage/
        'Early Stage Venture'
      when /late stage/
        'Late Stage Venture'
      when /funding raised/
        # Check amount to determine stage
        amount = clean_funding_amount(row)
        if amount > 30_000_000
          'Late Stage Venture'
        elsif amount > 10_000_000
          'Early Stage Venture'
        elsif amount > 0
          'Seed'
        else
          'Operating'
        end
      else
        # If no clear stage but has funding rounds or significant funding, assume Early Stage
        amount = clean_funding_amount(row)
        if row['Number of Funding Rounds'].to_i > 0 || amount > 1_000_000
          'Early Stage Venture'
        else
          # Default to Operating
          'Operating'
        end
      end
    end

    def clean_funding_amount(row)
      amount = row['Total Funding Amount (in USD)'].to_s.strip
      return 0 if amount.blank?

      # Remove any non-numeric characters except decimal points
      amount.gsub(/[^\d.]/, '').to_f
    end

  end
end
