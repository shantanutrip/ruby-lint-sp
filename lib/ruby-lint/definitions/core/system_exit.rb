# This file was automatically generated, any manual changes will be lost the
# next time this file is generated.
#
# Platform: rbx 2.2.3.n364

RubyLint.registry.register('SystemExit') do |defs|
  defs.define_constant('SystemExit') do |klass|
    klass.inherits(defs.constant_proxy('Exception', RubyLint.registry))

    klass.define_instance_method('initialize') do |method|
      method.define_optional_argument('first')
      method.define_rest_argument('args')

      method.returns { |object| object.instance }
    end

    klass.define_instance_method('status')

    klass.define_instance_method('success?')
  end
end
