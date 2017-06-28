class DefinitionListClass
  @@defHash
  def initialize
    @@defHash = Hash.new { |hash, key| hash[key] = Hash.new{|hash2, key2| hash2[key2] = Array.new} }
  end
  def self.defHash
    @@defHash
  end
  def self.defHashAdd(type, name, value)
    @@defHash[type][name].push(value)
  end
end