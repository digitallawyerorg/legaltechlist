namespace :logos do
    desc "Backfill missing company logos from verified domain logo URLs"
    task backfill: :environment do
        dry_run = ENV.fetch("DRY_RUN", "true") != "false"
        limit = ENV["LIMIT"].presence
        provider = ENV["PROVIDER"].presence

        puts "Starting logo backfill..."
        puts "Dry run: #{dry_run}"
        puts "Limit: #{limit || "none"}"
        puts "Provider: #{provider || "auto"}"

        result = LogoFetcherService.backfill_missing_logos(dry_run: dry_run, limit: limit, provider: provider)

        puts "\nLogo backfill completed!"
        puts "Checked: #{result.checked}"
        puts "Updated: #{result.updated}"
        puts "Skipped existing: #{result.skipped_existing}"
        puts "Skipped no domain: #{result.skipped_no_domain}"
        puts "Skipped unverified: #{result.skipped_unverified}"
        puts "Errors: #{result.errors}"
        puts "Examples:"
        result.examples.each do |example|
            puts "- #{example[:id]} | #{example[:name]} | #{example[:domain]} | #{example[:logo_url]}"
        end
    end

    desc "Fetch and save company logos"
    task fetch: :backfill
end
