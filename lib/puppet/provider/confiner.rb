require 'puppet/provider/confine_collection'

module Puppet::Provider::Confiner
  def confine(hash)
    confine_collection.confine(hash)
  end

  def confine_collection
    @confine_collection = Puppet::Provider::ConfineCollection.new(self.to_s) unless defined?(@confine_collection)
    @confine_collection
  end

  # Check whether this implementation is suitable for our platform.
  def suitable?(short = true)
    if short
      return confine_collection.valid?
    else
      return confine_collection.summary
    end
  end
end
