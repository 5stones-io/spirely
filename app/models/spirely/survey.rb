module Spirely
  # A survey a church asks families on its own site, with no sign-in
  # (5ST-84). Answers are anonymous (SurveyResponse).
  #
  # questions is a list of hashes:
  #   id        stable key answers are saved under
  #   type      single (pick one), multi (pick several) or text
  #   text      the question; hint is a line under it
  #   options   the choices (single and multi)
  #   max       for multi, how many may be picked
  #   other     adds an "Other" choice with a write-in
  #   follow_up a written question under the choices (e.g. "Why?")
  #   section   starts a new heading; note is shown under it
  #
  # Surveys come from templates in config/surveys/ (.from_template!).
  class Survey < ApplicationRecord
    STATUSES = %w[open closed].freeze
    TYPES = %w[single multi text].freeze
    OTHER = "Other".freeze
    MAX_TEXT = 2000
    TEMPLATE_DIR = Spirely::Engine.root.join("config/surveys")

    belongs_to :church
    has_many :responses, class_name: "Spirely::SurveyResponse", dependent: :delete_all

    validates :title, presence: true, length: { maximum: 200 }
    validates :slug, presence: true, format: { with: /\A[a-z0-9][a-z0-9-]*\z/ }, length: { maximum: 80 },
                     uniqueness: { scope: :church_id }
    validates :status, inclusion: { in: STATUSES }
    validate :questions_well_formed

    before_save :stamp_status_change

    scope :taking_answers, -> { where(status: "open") }

    def self.from_template!(church, template, slug:)
      path = TEMPLATE_DIR.join("#{template}.yml")
      raise ArgumentError, "no survey template named #{template}" unless template.to_s.match?(/\A[a-z0-9_]+\z/) && path.exist?

      data = YAML.safe_load(path.read, aliases: true)
      church.surveys.create!(
        slug: slug, title: data["title"], intro: data["intro"], thanks: data["thanks"], home_blurb: data["home_blurb"],
        questions: data["questions"].map { |q| normalize_question(q) },
      )
    end

    def self.normalize_question(q)
      { "id" => q["id"].to_s, "type" => q["type"], "text" => q["text"], "hint" => q["hint"],
        "section" => q["section"], "note" => q["note"], "options" => Array(q["options"]).map(&:to_s),
        "max" => q["max"], "other" => q["other"] == true, "follow_up" => q["follow_up"] }
    end

    def open? = status == "open"

    def question(id) = questions.find { |q| q["id"] == id.to_s }

    # What a response may hold: answers to this survey's own questions,
    # choices from their lists (up to max), and trimmed writing. Anything
    # else is dropped. An empty result means nothing was answered.
    def clean_answers(raw)
      raw = raw.to_unsafe_h if raw.respond_to?(:to_unsafe_h)
      return {} unless raw.is_a?(Hash)

      questions.each_with_object({}) do |q, out|
        given = raw[q["id"]] || raw[q["id"].to_sym]
        given = given.to_unsafe_h if given.respond_to?(:to_unsafe_h)
        next unless given.is_a?(Hash)

        given = given.stringify_keys
        answer = {}
        case q["type"]
        when "single"
          value = given["value"].to_s
          answer["value"] = value if q["options"].include?(value)
        when "multi"
          allowed = q["options"] + (q["other"] ? [OTHER] : [])
          picked = Array(given["value"]).map(&:to_s).select { |v| allowed.include?(v) }.uniq
          picked = picked.first(q["max"]) if q["max"]
          answer["value"] = picked if picked.any?
          other = text(given["other"])
          answer["other"] = other if other && picked.include?(OTHER)
        when "text"
          value = text(given["value"])
          answer["value"] = value if value
        end
        follow_up = q["follow_up"] && text(given["follow_up"])
        answer["follow_up"] = follow_up if follow_up
        out[q["id"]] = answer if answer.any?
      end
    end

    # Per question: how many answered, the count for each choice (in the
    # survey's order, Other last), and every write-in, newest first.
    def results
      rows = responses.order(created_at: :desc, id: :desc).pluck(:answers)
      questions.map do |q|
        given = rows.filter_map { |a| a[q["id"]] }
        result = { id: q["id"], answered: given.size }
        if q["type"] == "text"
          result[:texts] = given.filter_map { |a| a["value"] }
        else
          choices = q["options"] + (q["other"] ? [OTHER] : [])
          tally = given.flat_map { |a| Array(a["value"]) }.tally
          result[:counts] = choices.map { |c| [c, tally.fetch(c, 0)] }
          result[:other] = given.filter_map { |a| a["other"] } if q["other"]
        end
        result[:follow_ups] = given.filter_map { |a| a["follow_up"] } if q["follow_up"]
        result
      end
    end

    private

    def text(value)
      value = value.to_s.strip
      value.presence && value[0, MAX_TEXT]
    end

    def stamp_status_change
      return unless new_record? || will_save_change_to_status?
      if open?
        self.opened_at ||= Time.current
        self.closed_at = nil
      else
        self.closed_at = Time.current
      end
    end

    def questions_well_formed
      unless questions.is_a?(Array) && questions.any?
        errors.add(:questions, "must list at least one question")
        return
      end
      ids = questions.map { |q| q["id"] }
      errors.add(:questions, "need unique ids") if ids.any?(&:blank?) || ids.uniq.size != ids.size
      questions.each do |q|
        errors.add(:questions, "#{q['id']}: unknown type #{q['type']}") unless TYPES.include?(q["type"])
        errors.add(:questions, "#{q['id']}: needs text") if q["text"].blank?
        if q["type"] != "text" && q["options"].blank?
          errors.add(:questions, "#{q['id']}: needs options")
        end
      end
    end
  end
end
