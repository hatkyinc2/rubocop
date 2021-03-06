# frozen_string_literal: true

module RuboCop
  module Cop
    module Lint
      # This cop ensures that `to_enum`/`enum_for`, called for the current method,
      # has correct arguments.
      #
      # @example
      #   # bad
      #   def method(x, y = 1)
      #     return to_enum(__method__, x) # `y` is missing
      #   end
      #
      #   # good
      #   def method(x, y = 1)
      #     return to_enum(__method__, x, y)
      #   end
      #
      #   # bad
      #   def method(required:)
      #     return to_enum(:method, required: something) # `required` has incorrect value
      #   end
      #
      #   # good
      #   def method(required:)
      #     return to_enum(:method, required: required)
      #   end
      #
      class ToEnumArguments < Base
        MSG = 'Ensure you correctly provided all the arguments.'

        RESTRICT_ON_SEND = %i[to_enum enum_for].freeze

        def_node_matcher :enum_conversion_call?, <<~PATTERN
          (send {nil? self} {:to_enum :enum_for} $_ $...)
        PATTERN

        def_node_matcher :method_name?, <<~PATTERN
          {(send nil? :__method__) (sym %1)}
        PATTERN

        def_node_matcher :passing_keyword_arg?, <<~PATTERN
          (pair (sym %1) (lvar %1))
        PATTERN

        # TODO: add support for argument forwarding (`...`) when ruby 3.0 is released
        def on_send(node)
          def_node = node.each_ancestor(:def, :defs).first
          return unless def_node

          enum_conversion_call?(node) do |method_node, arguments|
            add_offense(node) unless method_name?(method_node, def_node.method_name) &&
                                     arguments_match?(arguments, def_node)
          end
        end

        private

        def arguments_match?(arguments, def_node)
          index = 0

          def_node.arguments.reject(&:blockarg_type?).all? do |def_arg|
            send_arg = arguments[index]
            case def_arg.type
            when :arg, :restarg, :optarg
              index += 1
            end

            send_arg && argument_match?(send_arg, def_arg)
          end
        end

        # rubocop:disable Metrics/AbcSize, Metrics/CyclomaticComplexity
        def argument_match?(send_arg, def_arg)
          def_arg_name = def_arg.children[0]

          case def_arg.type
          when :arg, :restarg
            send_arg.source == def_arg.source
          when :optarg
            send_arg.source == def_arg_name.to_s
          when :kwoptarg, :kwarg
            send_arg.hash_type? &&
              send_arg.pairs.any? { |pair| passing_keyword_arg?(pair, def_arg_name) }
          when :kwrestarg
            send_arg.each_child_node(:kwsplat).any? { |child| child.source == def_arg.source }
          end
        end
        # rubocop:enable Metrics/AbcSize, Metrics/CyclomaticComplexity
      end
    end
  end
end
