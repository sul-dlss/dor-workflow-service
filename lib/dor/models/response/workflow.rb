# frozen_string_literal: true

require 'dor/models/response/process'

module Dor
  module Workflow
    module Response
      # The response from asking the server about a workflow for an item
      class Workflow
        def initialize(xml:)
          @xml = xml
        end

        def pid
          ng_xml.at_xpath('/workflow/@objectId').text
        end

        def workflow_name
          ng_xml.at_xpath('/workflow/@id').text
        end

        # @param [Integer] version the version we are checking for.
        def active_for?(version:)
          result = ng_xml.at_xpath("/workflow/process[@version=#{version}]")
          result ? true : false
        end

        # Returns the process, for the most recent version that matches the given name:
        def process_for_recent_version(name:)
          nodes = process_nodes_for(name: name)
          node = nodes.max { |a, b| a.attr('version').to_i <=> b.attr('version').to_i }
          attributes = node ? Hash[node.attributes.collect { |k, v| [k.to_sym, v.value] }] : {}
          Process.new(parent: self, **attributes)
        end

        def empty?
          ng_xml.xpath('/workflow/process').empty?
        end

        attr_reader :xml

        private

        def process_nodes_for(name:)
          ng_xml.xpath("/workflow/process[@name = '#{name}']")
        end

        def ng_xml
          @ng_xml ||= Nokogiri::XML(@xml)
        end
      end
    end
  end
end
