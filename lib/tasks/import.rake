#lib/tasks/import.rake

desc 'Import LTCs'

require 'csv'

namespace :csv do

	task :import => :environment do
    unless ENV["ALLOW_LEGACY_CSV_IMPORT"] == "true"
      abort "Legacy csv:import is disabled. Use ImportCsvToCompanyService or set ALLOW_LEGACY_CSV_IMPORT=true."
    end

		CSV.foreach("#{Rails.root}/lib/presentation_data_03.csv", :headers => true, :encoding => 'UTF-8') do |row|
      row.to_hash
      #9_3_set_2
      #row["category"] = Category.where(:name => row["category"]).first_or_create!
      #Company.create(row)

      # clean up data to ensure validation on import
      # Removing employee count for now
      # count = row["employee_count"].to_i
      # if count.nil?
      #   count = 1
      # elsif count < 1
      #   count = 1
      # end

      # Add placeholder when no location is present
      if row["location"].nil? || row["location"] == ""
        row["location"] = "No location yet"
      end

      # Add placeholder when no category is present
      if row["category"].nil? || row["category"] == ""
        row["category"] = "Unknown"
      end

      # Add placeholder when no founded_date is present
      if row["founded_date"].nil? || row["founded_date"] == ""
        row["founded_date"] = "0000"
      end

      if row["description"].nil? || row["description"] == ""
        row["description"] = "No description yet"
      end


      if row["business_model"].nil? || row["business_model"] == ""
        row["business_model"] = "Unknown"
      end

      if row["business_model"].nil? || row["business_model"] == ""
        row["business_model"] = "Unknown"
      end

      if row["all_tags"].nil? || row["all_tags"] == ""
        row["all_tags"] = ""
      end

      if row["target_client"].nil? || row["target_client"] == ""
        row["target_client"] = "Unknown"
      end

      if row["linkedin_url"].nil? || row["linkedin_url"] == ""
        row["linkedin_url"] = "Unknown"
      end

      if row["facebook_url"].nil? || row["facebook_url"] == ""
        row["facebook_url"] = "Unknown"
      end

      if row["legalio_url"].nil? || row["legalio_url"] == ""
        row["legalio_url"] = "Unknown"
      end

      if row["status"].nil? || row["status"] == ""
        row["status"] = "Unknown"
      end

      # split category into category and sub-category
      catFullname = row["category"].split('-')
      catName = catFullname[0].strip
      if catFullname[1].nil?
        catFullname[1]=""
      end

      cat = TaxonomyNormalizationService.find_category(row["category"]) || Category.find_by(name: "Unknown")
      sub = nil
      if catFullname[1].present?
        sub = SubCategory.find_by(name: catFullname[1].strip, category: cat)
      end

      revenue_models = TaxonomyNormalizationService.find_revenue_models(row["business_model"])
      revenue_models = [BusinessModel.find_by(name: "Other")].compact if revenue_models.empty?
      biz = revenue_models.first
      target_clients = TaxonomyNormalizationService.find_target_clients(row["target_client"])
      trg = target_clients.first || TargetClient.find_by(name: "Unknown")

      # add the entry to the database
      c = Company.where(:name => row["name"]).first_or_create!(
        :name => row["name"].to_s.encode('UTF-8', invalid: :replace, undef: :replace, replace: ''),
        :location => row["location"],
        :founded_date => row["founded_date"],
        :category => cat,
        :sub_category => sub,
        :description => row["description"].to_s.encode('UTF-8', invalid: :replace, undef: :replace, replace: ''),
        :main_url => row["main_url"],
        :twitter_url => row["twitter_url"],
        :angellist_url => row["angellist_url"],
        :crunchbase_url => row["crunchbase_url"],
        :linkedin_url => row["linkedin_url"],
        :facebook_url => row["facebook_url"],
        :legalio_url => row["legalio_url"],
        :status => row["status"],
        :business_model => biz,
        :target_client => trg,
        :all_tags => row["all_tags"]
      )
      c.business_model_ids = revenue_models.map(&:id) if c.persisted?
      c.target_client_ids = target_clients.map(&:id) if c.persisted? && target_clients.any?

    end
	end
end

namespace :import do
  desc "Import companies from CSV file"
  task companies: :environment do
    input_file = 'input.csv'

    unless File.exist?(input_file)
      puts "Error: Could not find #{input_file}"
      exit 1
    end

    # Create a temporary uploaded file object that ImportCsvToCompanyService expects
    temp_file = ActionDispatch::Http::UploadedFile.new(
      tempfile: File.open(input_file),
      filename: File.basename(input_file),
      type: 'text/csv'
    )

    puts "Starting import from #{input_file}..."
    stats = ImportCsvToCompanyService.import(temp_file)

    puts "\nImport completed!"
    puts "Created: #{stats[:created]}"
    puts "Updated: #{stats[:updated]}"
    puts "Skipped: #{stats[:skipped]}"
    puts "Errors: #{stats[:errors]}"
  end
end
