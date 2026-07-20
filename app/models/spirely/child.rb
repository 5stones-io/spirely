module Spirely
  class Child < ApplicationRecord
    GRADE_DISPLAY = {
      0 => "K",    1 => "1st",  2 => "2nd",  3 => "3rd",
      4 => "4th",  5 => "5th",  6 => "6th",  7 => "7th",
      8 => "8th",  9 => "9th",  10 => "10th", 11 => "11th", 12 => "12th"
    }.freeze

    GRADE_PARSE = {
      "k" => 0, "kindergarten" => 0,
      "1" => 1, "1st" => 1,  "2" => 2,  "2nd" => 2,  "3" => 3,  "3rd" => 3,
      "4" => 4, "4th" => 4,  "5" => 5,  "5th" => 5,  "6" => 6,  "6th" => 6,
      "7" => 7, "7th" => 7,  "8" => 8,  "8th" => 8,  "9" => 9,  "9th" => 9,
      "10" => 10, "10th" => 10, "11" => 11, "11th" => 11, "12" => 12, "12th" => 12
    }.freeze

    belongs_to :family

    validates :first_name, :last_name, presence: true
    validates :grade, numericality: { in: 0..12, only_integer: true }, allow_nil: true

    # Accept PCO integer or human string ("3rd", "K") — store as integer
    def grade=(val)
      if val.is_a?(Integer) || val.nil?
        super(val)
      else
        super(GRADE_PARSE[val.to_s.strip.downcase])
      end
    end

    # Human-readable display ("3rd", "K") for the UI
    def grade_display
      GRADE_DISPLAY[grade]
    end

    def full_name
      "#{first_name} #{last_name}"
    end

    def age
      return nil if birthdate.nil?
      today = Date.current
      years = today.year - birthdate.year
      years -= 1 if today < birthdate + years.years
      years
    end
  end
end
