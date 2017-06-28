require_relative 'lib/ruby-lint'
require_relative 'definition_list_class'

#definitionsCode = build_definitions(code)

@obj = DefinitionListClass.new
command = RubyLint::Command.new()
#puts "Hi"
args = ["~/AttemptRuby/"]
command.run(args)
puts "ruby-req_Hi"
obj = (command.vm).definitions
#puts obj
#puts obj.definitions
puts "FirstTrip"
#@first = obj.lookup(:instance_method, 'increaseGlobal')
#puts @first
definitions = DefinitionListClass.defHash
puts definitions
definitions.each{|type, lst|
  puts "entry"
  puts type
  lst.each{|name, values|
    #puts name
    if name != 'func'
      next
    end
    puts name
    values.each{|value|
      if value.is_a?(RubyLint::Definition::RubyMethod)
        puts "calls"
        #puts value.calls
        (value.calls).each{ |call|
          puts call.line
          puts call.file
          puts call.column
        }
        #puts value.calls[0].line
        #puts value.calls[1].line
        puts "callers"
        #puts value.callers
        (value.callers).each{ |caller|
          puts caller.line
          puts caller.file
          puts caller.column
        }
        puts "calls end"
      end
    }
  }
}


#puts definitions.is_a?(Hash)
#puts DefinitionListClass.defHash