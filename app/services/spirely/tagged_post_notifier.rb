module Spirely
  # Emails each family tagged in a staff post (5ST-78): the family's own
  # address and its guardians', each address once.
  class TaggedPostNotifier
    def self.feed_url(church)
      "https://#{church.primary_hostname}/family-feed"
    end

    def self.posted(post)
      post.tagged_children.includes(family: { guardians: :account }).map(&:family).uniq.each do |family|
        emails = [family.email, *family.guardians.map { |g| g.email.presence || g.account&.email }]
        emails.compact_blank.map(&:downcase).uniq.each do |email|
          Spirely::TaggedPostMailer.tagged(post, family, email).deliver_later
        end
      end
    end
  end
end
