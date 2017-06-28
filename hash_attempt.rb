hsh = Hash.new { |hash, key| hash[key] = Hash.new{|hash2, key2| hash2[key2] = Array.new} }
hsh["1"]["2"].push(3)
hsh["4"]["5"]<<6
hsh["4"]["5"]<<7
puts hsh["4"]["5"][0]