require 'spec_helper'

describe RubyLint::VirtualMachine do
  it 'makes variables available in a block' do
    code = <<-CODE
number = 10

example do
end
    CODE

    definition = build_associations(code).to_a.last.last

    number = definition.lookup(:lvar, 'number')

    number.is_a?(ruby_object).should == true
    number.value.value.should        == 10
  end

  it 'makes block arguments available as variables inside the block only' do
    code = <<-CODE
example do
  number = 10
end
    CODE

    associations = build_associations(code).to_a

    root_def  = associations.first.last
    block_def = associations.last.last

    root_def.lookup(:lvar, 'number').nil?.should         == true
    block_def.lookup(:lvar, 'number').value.value.should == 10
  end

  it 'blocks should be instances by default' do
    code = <<-CODE
example do
end
    CODE

    block = build_associations(code).to_a.last.last

    block.type.should          == :block
    block.instance_type.should == :instance
  end

  it 'blocks should inherit the instance type from the outer scope' do
    code = <<-CODE
class A
  example do
  end
end
    CODE

    block = build_associations(code).to_a.last.last

    block.type.should          == :block
    block.instance_type.should == :class
  end

  it 'updates outer variables modified in the block' do
    code = <<-CODE
number   = 10
@number  = 10
@@number = 10
$number  = 10

example do
  number   = 20
  @number  = 20
  @@number = 20
  $number  = 20
end
    CODE

    defs = build_definitions(code)

    variables = {
      :lvar => 'number',
      :ivar => '@number',
      :cvar => '@@number',
      :gvar => '$number'
    }

    variables.each do |type, name|
      defs.lookup(type, name).value.value.should == 20
    end
  end
end
