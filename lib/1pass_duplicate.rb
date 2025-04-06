require "thor"
require "colorize"
require "json"
require "uri"
require "public_suffix"
require "fileutils"

class OnePasswordDuplicate < Thor
  desc "detect", "Detect duplicate items in 1Password vault"
  option :vault, type: :string, required: true, desc: "Vault name to check for duplicates"
  option :dry_run, type: :boolean, default: true, desc: "Only show duplicates without removing them"
  option :clear_cache, type: :boolean, default: false, desc: "Clear the cache before running"

  CACHE_DIR = File.expand_path("~/.cache/1pass_duplicate")

  def detect
    setup_cache
    clear_cache if options[:clear_cache]

    puts "🔍 Scanning vault '#{options[:vault]}' for duplicates...".yellow

    # Get all items from the vault
    items = get_vault_items(options[:vault])

    # Group items by potential duplicates
    duplicates = find_duplicates(items)

    # Display results
    display_results(duplicates, options[:dry_run])

    # Archive duplicates if not in dry run mode
    archive_duplicates(duplicates) unless options[:dry_run]
  end

  private

  def setup_cache
    FileUtils.mkdir_p(CACHE_DIR)
  end

  def clear_cache
    puts "Clearing cache...".yellow
    FileUtils.rm_rf(Dir.glob("#{CACHE_DIR}/*"))
  end

  def cache_path(item_id, vault_name)
    File.join(CACHE_DIR, "#{vault_name}-#{item_id}.json")
  end

  def get_item_details(item_id, vault_name)
    cache_file = cache_path(item_id, vault_name)

    if File.exist?(cache_file)
      JSON.parse(File.read(cache_file))
    else
      details = JSON.parse(`op item get "#{item_id}" --format json`)
      File.write(cache_file, JSON.pretty_generate(details))
      details
    end
  end

  def extract_base_domain(host)
    return nil if host.nil?

    # Remove www. if present
    host = host.sub(/^www\./, "")

    # Remove common login/account subdomains
    host = host.sub(/^(account|login|app|my|secure|member|auth)\./, "")

    host
  end

  def normalize_url(url)
    return nil if url.nil? || url.empty?

    begin
      # Parse the URL
      uri = URI.parse(url)
      return nil unless uri.host

      # Get the base domain
      base_domain = extract_base_domain(uri.host)

      # Return just the domain - ignore paths for matching
      "https://#{base_domain}"
    rescue URI::InvalidURIError
      url
    end
  end

  def get_vault_items(vault_name)
    begin
      # Get vault ID from vault name
      puts "Getting vault list...".yellow
      vaults_output = `op vault list --format json`
      vaults = JSON.parse(vaults_output)
      vault = vaults.find { |v| v["name"] == vault_name }

      unless vault
        puts "Error: Vault '#{vault_name}' not found".red
        exit 1
      end

      # Get all items from the vault with detailed information
      puts "Getting items from vault...".yellow
      items_output = `op item list --vault "#{vault_name}" --format json`
      items = JSON.parse(items_output)

      # Get full details for each item
      puts "Getting full item details...".yellow
      total = items.size
      items.map.with_index do |item, index|
        begin
          print "\rProcessing item #{index + 1}/#{total}"
          details = get_item_details(item["id"], vault_name)
          username_field = details["fields"]&.find { |f| f["purpose"] == "USERNAME" }
          password_field = details["fields"]&.find { |f| f["purpose"] == "PASSWORD" }
          original_url = details["urls"]&.first&.dig("href")

          {
            id: item["id"],
            title: item["title"],
            url: original_url,
            normalized_url: normalize_url(original_url),
            username: username_field&.dig("value"),
            password: password_field&.dig("value"),
            updated_at: item["updated_at"],
            vault_id: vault["id"],
          }
        rescue => e
          puts "\nError getting details for item #{item["id"]}: #{e.message}".red
          nil
        end
      end.compact
    rescue JSON::ParserError => e
      puts "Error parsing 1Password output: #{e.message}".red
      exit 1
    rescue => e
      puts "Error accessing 1Password: #{e.message}".red
      puts "Backtrace: #{e.backtrace.join("\n")}".red
      exit 1
    end
  end

  def find_duplicates(items)
    # Group items by their identifying characteristics
    duplicates = {}

    items.each do |item|
      # Create a key based on normalized URL, username, and password only
      # Skip title as it can be misleading
      key = [
        item[:normalized_url],
        item[:username],
        item[:password],
      ].compact.join("|")

      # Skip if there's not enough information to match on
      next if key.empty?

      duplicates[key] ||= []
      duplicates[key] << item
    end

    # Filter out non-duplicates (only keep entries with 2 or more items)
    duplicates.select { |_, items| items.size > 1 }
  end

  def display_results(duplicates, dry_run)
    if duplicates.empty?
      puts "✅ No duplicates found!".green
      return
    end

    puts "\nFound #{duplicates.size} sets of duplicates:".yellow
    duplicates.each do |key, items|
      puts "\nDuplicate set:".cyan
      items.each do |item|
        puts "  - #{item[:title]} (#{item[:id]})"
        puts "    Original URL: #{item[:url]}" if item[:url]
        puts "    Normalized URL: #{item[:normalized_url]}" if item[:normalized_url]
        puts "    Username: #{item[:username]}" if item[:username]
        puts "    Last updated: #{item[:updated_at]}"
      end
    end

    if dry_run
      puts "\nThis was a dry run. No items were archived.".yellow
      puts "Run with --no-dry-run to archive duplicates.".yellow
    end
  end

  def archive_duplicates(duplicates)
    puts "\nArchiving duplicates...".yellow

    duplicates.each do |_, items|
      # Sort by updated_at to keep the most recent version
      items.sort_by! { |item| item[:updated_at] }

      # Keep the most recent item
      items_to_keep = items.pop

      # Archive all other items
      items.each do |item|
        begin
          system("op item delete '#{item[:id]}' --vault '#{options[:vault]}' --archive")
          puts "Archived: #{item[:title]} (#{item[:id]})".yellow
          # Remove the cached item since it's been archived
          FileUtils.rm_f(cache_path(item[:id], options[:vault]))
        rescue => e
          puts "Error archiving item #{item[:id]}: #{e.message}".red
        end
      end
    end
  end
end

OnePasswordDuplicate.start(ARGV)
