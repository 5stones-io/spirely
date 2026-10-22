module Spirely
  # Paging and rate-limit handling shared by the read-only PCO mirrors
  # (PcoGroupsSyncJob, PcoServicesSyncJob). The including job sets @client.
  module PcoFetching
    RATE_LIMIT_PAUSE = 20 # seconds — PCO allows ~100 requests per 20s
    MAX_RATE_RETRIES = 3

    private

    def save_if_changed(record)
      record.save! if record.new_record? || record.changed?
      record
    end

    def index_included(included, type)
      Array(included).select { |r| r["type"] == type }.index_by { |r| r["id"] }
    end

    # Follows links.next like PcoClient#paginate, but retries a 429 on the
    # page that hit it instead of failing the whole sync. A block can stop
    # paging early by returning false for a page.
    def fetch_all(path, params = {}, with_included: false)
      data, included = [], []
      query = params.merge("per_page" => Spirely::PcoClient::PAGE_SIZE)

      loop do
        page = get_with_retry(path, query)
        data.concat(Array(page["data"]))
        included.concat(Array(page["included"]))
        break if block_given? && yield(Array(page["data"])) == false

        next_link = page.dig("links", "next").presence
        break unless next_link

        uri   = URI.parse(next_link)
        path  = uri.path
        query = URI.decode_www_form(uri.query.to_s).to_h
      end

      with_included ? { data: data, included: included } : data
    end

    def get_with_retry(path, query, attempt: 0)
      @client.get(path, query)
    rescue Spirely::PcoApiError => e
      raise unless e.status == 429 && attempt < MAX_RATE_RETRIES

      sleep RATE_LIMIT_PAUSE
      get_with_retry(path, query, attempt: attempt + 1)
    end
  end
end
