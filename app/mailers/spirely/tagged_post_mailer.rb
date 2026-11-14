module Spirely
  class TaggedPostMailer < ApplicationMailer
    # "Maria Rivera posted about Emma" — to a family whose children a staff
    # post tags (5ST-78), linking to their feed.
    def tagged(post, family, to)
      @post   = post
      @church = post.church
      @author = Spirely::FamilyPost.author_name(post)
      @names  = post.tagged_children.select { |c| c.family_id == family.id }.map(&:first_name).sort.to_sentence
      @url    = Spirely::TaggedPostNotifier.feed_url(@church)
      mail(to: to, subject: "#{@author} posted about #{@names}")
    end
  end
end
