module RubyLint
  class VirtualMachine < Iterator
    include Helper::ConstantPaths

    attr_reader :associations, :definitions

    attr_reader :value_stack, :variable_stack

    private :value_stack, :variable_stack

    ##
    # Hash containing the definition types to copy when including/extending a
    # module.
    #
    # @return [Hash]
    #
    INCLUDE_CALLS = {
      'include' => {
        :const           => :const,
        :instance_method => :instance_method
      },
      'extend' => {
        :const           => :const,
        :instance_method => :method
      }
    }

    ASSIGNMENT_TYPES = {
      :lvasgn => :lvar,
      :ivasgn => :ivar,
      :cvasgn => :cvar,
      :gvasgn => :gvar
    }

    PRIMITIVES = [:int, :float, :str, :sym]

    SEND_MAPPING = {'[]=' => 'assign_member'}

    ##
    # Called after a new instance of the virtual machine has been created.
    #
    def after_initialize
      @associations   = {}
      @definitions    = initial_definitions
      @scopes         = [@definitions]
      @in_sclass      = false
      @value_stack    = NestedStack.new
      @variable_stack = NestedStack.new
      @ignored_nodes  = []

      reset_method_type
    end

    def on_assign(node)
      reset_assignment_value
      value_stack.add_stack
    end

    def after_assign(node)
      values = value_stack.pop

      if values.empty? and assignment_value
        values = [assignment_value]
      end

      variable = Definition::RubyObject.new(
        :type          => ASSIGNMENT_TYPES[node.type],
        :name          => node.children[0].to_s,
        :value         => values.first, # TODO: handle multiple values
        :instance_type => :instance
      )

      buffer_assignment_value(variable.value)

      add_variable(variable)
    end

    ASSIGNMENT_TYPES.each do |callback, type|
      alias :"on_#{callback}" :on_assign
      alias :"after_#{callback}" :after_assign
    end

    def on_casgn(node)
      # Don't push values for the receiver constant.
      @ignored_nodes << node.children[0] if node.children[0]

      reset_assignment_value
      value_stack.add_stack
    end

    def after_casgn(node)
      values = value_stack.pop
      scope  = current_scope

      if node.children[0]
        scope = resolve_constant_path(node.children[0])

        return unless scope
      end

      variable = Definition::RubyObject.new(
        :type          => :const,
        :name          => node.children[1].to_s,
        :value         => values.first,
        :instance_type => :instance
      )

      add_variable(variable, scope)
    end

    def on_masgn(node)
      value_stack.add_stack
      variable_stack.add_stack
    end

    def after_masgn(node)
      variables = variable_stack.pop
      values    = value_stack.pop

      variables.each_with_index do |variable, index|
        variable.value = values[index]

        current_scope.add(variable.type, variable.name, variable)
      end
    end

    PRIMITIVES.each do |type|
      define_method("on_#{type}") do |node|
        push_value(create_primitive(node))
      end
    end

    ASSIGNMENT_TYPES.each do |asgn_name, type|
      define_method("on_#{type}") do |node|
        push_variable_value(node)
      end
    end

    def on_const(node)
      push_variable_value(node)
    end

    def on_array(node)
      value_stack.add_stack
    end

    def after_array(node)
      values     = value_stack.pop
      definition = Definition::RubyObject.new(
        :type             => :array,
        :instance_type    => :instance,
        :parents          => [RubyLint.global_constant('Array')],
        :members_as_value => true
      )

      values.each_with_index do |value, index|
        index  = index.to_s
        member = Definition::RubyObject.new(
          :type  => :member,
          :name  => index,
          :value => value
        )

        definition.add_definition(member)
      end

      push_value(definition)
    end

    def on_module(node)
      define_module(node, DefinitionBuilder::RubyModule)
    end

    def after_module(node)
      pop_scope
    end

    def on_class(node)
      define_module(node, DefinitionBuilder::RubyClass)
    end

    def after_class(node)
      pop_scope
    end

    def on_sclass(node)
      receiver = node.children[0]

      if receiver.self?
        definition = current_scope.lookup(:keyword, 'self')
      else
        definition = current_scope.lookup(receiver.type, receiver.name)
      end

      associate_node(node, definition)

      push_scope(definition)

      @method_type = :method
    end

    def after_sclass(node)
      reset_method_type
      pop_scope
    end

    def on_def(node)
      builder = DefinitionBuilder::RubyMethod.new(
        node,
        current_scope,
        :type => @method_type
      )

      definition = builder.build

      builder.scope.add_definition(definition)

      associate_node(node, definition)

      push_scope(definition)
    end

    def after_def(node)
      pop_scope
    end

    alias on_defs on_def
    alias after_defs after_def

    def on_send(node)
      name     = node.children[1].to_s
      name     = SEND_MAPPING.fetch(name, name)
      callback = "on_send_#{name}"

      execute_callback(callback, node)
    end

    def after_send(node)
      name     = node.children[1].to_s
      name     = SEND_MAPPING.fetch(name, name)
      callback = "after_send_#{name}"

      execute_callback(callback, node)
    end

    def on_send_include(node)
      value_stack.add_stack
    end

    def after_send_include(node)
      copy_types = INCLUDE_CALLS[node.children[1].to_s]
      scope      = current_scope
      arguments  = value_stack.pop

      arguments.each do |source|
        copy_types.each do |from, to|
          source.list(from).each do |definition|
            scope.add(to, definition.name, definition)
          end
        end
      end
    end

    alias on_send_extend on_send_include
    alias after_send_extend after_send_include

    def on_send_assign_member(node)
      value_stack.add_stack
    end

    def after_send_assign_member(node)
      array, *indexes, values = value_stack.pop

      if values.array?
        values = values.list(:member).map(&:value)
      else
        values = [values]
      end

      indexes.each do |index|
        member = Definition::RubyObject.new(
          :name  => index.value.to_s,
          :type  => :member,
          :value => values.shift
        )

        array.add_definition(member)
      end
    end

    private

    ##
    # Returns the initial set of definitions to use.
    #
    # @return [RubyLint::Definition::RubyObject]
    #
    def initial_definitions
      definitions = Definition::RubyObject.new(
        :name          => 'root',
        :type          => :root,
        :parents       => [RubyLint.global_constant('Kernel')],
        :instance_type => :instance
      )

      definitions.merge(RubyLint.global_scope)

      return definitions
    end

    ##
    # Defines a new module/class based on the supplied node.
    #
    # @param [RubyLint::Node] node
    # @param [Class] definition_builder
    #
    def define_module(node, definition_builder)
      builder    = definition_builder.new(node, current_scope)
      definition = builder.build
      scope      = builder.scope
      existing   = scope.lookup(definition.type, definition.name)

      if existing
        definition = existing

        unless definition.parents.include?(current_scope)
          definition.parents << current_scope
        end
      else
        scope.add_definition(definition)
      end

      associate_node(node, definition)

      push_scope(definition)
    end

    ##
    # @return [RubyLint::Definition::RubyObject]
    #
    def current_scope
      return @scopes.last
    end

    ##
    # Associates the given node and defintion with each other.
    #
    # @param [RubyLint::AST::Node] node
    # @param [RubyLint::Definition::RubyObject] definition
    #
    def associate_node(node, definition)
      @associations[node] = definition
    end

    ##
    # Pushes a new scope on the list of available scopes.
    #
    # @param [RubyLint::Definition::RubyObject] definition
    #
    def push_scope(definition)
      @scopes << definition
    end

    ##
    # Removes a scope from the list.
    #
    # TODO: raise an error when trying to pop the stack when it is already
    # empty.
    #
    def pop_scope
      @scopes.pop
    end

    def push_variable_value(node)
      return if value_stack.empty? || @ignored_nodes.include?(node)

      if node.const? and node.children[0]
        definition = resolve_constant_path(node)
      else
        definition = current_scope.lookup(node.type, node.variable_name)
      end

      value = definition.value ? definition.value : definition

      push_value(value)
    end

    def push_value(definition)
      value_stack.push(definition) if definition && !value_stack.empty?
    end

    def add_variable(variable, scope = current_scope)
      if variable_stack.empty?
        scope.add(variable.type, variable.name, variable)
      else
        variable_stack.push(variable)
      end
    end

    def create_primitive(node, options = {})
      builder = DefinitionBuilder::Primitive.new(node, current_scope, options)

      return builder.build
    end

    def reset_assignment_value
      @assignment_value = nil
    end

    def assignment_value
      return @assignment_value
    end

    def buffer_assignment_value(value)
      @assignment_value = value
    end

    def reset_method_type
      @method_type = :instance_method
    end
  end # VirtualMachine
end # RubyLint
