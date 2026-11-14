module Spirely
  # Family#address is one free-text string ("10718 John Turley Pl, Fairfax,
  # VA, 22032" from Quick-Add, "street, city, ST zip" from inbound sync);
  # a PCO Address is street_line_1/street_line_2/city/state/zip. This
  # converts between the two and writes a family's address to PCO.
  module PcoAddress
    ZIP   = /,?\s*(\d{5}(?:-\d{4})?)\s*\z/
    STATE = /,?\s*\b([A-Za-z]{2})\s*\z/

    module_function

    # Best effort: ZIP and two-letter state off the end, then the first
    # comma-separated part is the street and the rest is the city. Anything
    # that doesn't split that way goes into street_line_1 whole, so nothing
    # typed is lost.
    def parse(address)
      rest = address.to_s.strip
      return nil if rest.empty?

      zip   = rest[ZIP, 1]
      rest  = rest.sub(ZIP, "") if zip
      state = rest[STATE, 1]
      rest  = rest.sub(STATE, "") if state

      street, *city = rest.split(",").map(&:strip).reject(&:empty?)
      if city.empty?
        return { street_line_1: address.to_s.strip } unless zip || state
        city = nil
      else
        city = city.join(", ")
      end

      { street_line_1: street, city: city, state: state&.upcase, zip: zip }.compact
    end

    # PCO replaced `street` with street_line_1/street_line_2; `street` is
    # still read as a fallback for older records.
    def format(record)
      return nil unless record
      a = record["attributes"] || {}
      street = [a["street_line_1"], a["street_line_2"]].map(&:presence).compact.join(" ").presence || a["street"]
      [
        street,
        a["city"],
        [a["state"], a["zip"]].map(&:presence).compact.join(" ")
      ].map(&:presence).compact.join(", ").presence
    end

    # Updates the person's primary (or first) address, or adds one as their
    # primary Home address. Never removes an address from PCO. A rejected
    # address is logged, not raised, so it can't fail the rest of a sync.
    def push(client, pco_person_id, address)
      attrs = parse(address)
      return unless attrs

      path     = "/people/v2/people/#{pco_person_id}/addresses"
      existing = client.get(path)["data"] || []
      current  = existing.find { |r| r.dig("attributes", "primary") } || existing.first

      if current
        return if format(current) == format("attributes" => attrs.transform_keys(&:to_s))

        client.patch("#{path}/#{current["id"]}", {
          data: { type: "Address", id: current["id"], attributes: attrs }
        })
      else
        client.post(path, {
          data: { type: "Address", attributes: attrs.merge(location: "Home", primary: true) }
        })
      end
    rescue Spirely::PcoError => e
      Rails.logger.error("[Spirely] PcoAddress: PCO rejected the address for person #{pco_person_id}: #{e.message}")
    end
  end
end
