# frozen_string_literal: true

module Dor
  module Workflow
    class Client
      # Makes requests relating to a workflow
      class WorkflowRoutes
        def initialize(requestor:)
          @requestor = requestor
        end

        # Creates a workflow for a given object in the repository.  If this particular workflow for this objects exists,
        # it will replace the old workflow with wf_xml passed to this method.  You have the option of creating a datastream or not.
        # Returns true on success.  Caller must handle any exceptions
        #
        # @param [String] repo The repository the object resides in.  The service recoginzes "dor" and "sdr" at the moment
        # @param [String] druid The id of the object
        # @param [String] workflow_name The name of the workflow you want to create
        # @param [String] wf_xml The xml that represents the workflow
        # @param [Hash] opts optional params
        # @option opts [Boolean] :create_ds if true, a workflow datastream will be created in Fedora.  Set to false if you do not want a datastream to be created
        #   If you do not pass in an <b>opts</b> Hash, then :create_ds is set to true by default
        # @option opts [String] :lane_id adds laneId attribute to all process elements in the wf_xml workflow xml.  Defaults to a value of 'default'
        # @return [Boolean] always true
        #
        def create_workflow(repo, druid, workflow_name, wf_xml, opts = { create_ds: true })
          lane_id = opts.fetch(:lane_id, 'default')
          xml = add_lane_id_to_workflow_xml(lane_id, wf_xml)
          _status = requestor.request "#{repo}/objects/#{druid}/workflows/#{workflow_name}", 'put', xml,
                                      content_type: 'application/xml',
                                      params: { 'create-ds' => opts[:create_ds] }
          true
        end

        # Updates the status of one step in a workflow.
        # Returns true on success.  Caller must handle any exceptions
        #
        # @param [String] repo The repository the object resides in.  The service recoginzes "dor" and "sdr" at the moment
        # @param [String] druid The id of the object
        # @param [String] workflow The name of the workflow
        # @param [String] process The name of the process step
        # @param [String] status The status that you want to set -- using one of the values in VALID_STATUS
        # @param [Hash] opts optional values for the workflow step
        # @option opts [Float] :elapsed The number of seconds it took to complete this step. Can have a decimal.  Is set to 0 if not passed in.
        # @option opts [String] :lifecycle Bookeeping label for this particular workflow step.  Examples are: 'registered', 'shelved'
        # @option opts [String] :note Any kind of string annotation that you want to attach to the workflow
        # @option opts [String] :lane_id Id of processing lane used by the job manager.  Can convey priority or name of an applicaiton specific processing lane (e.g. 'high', 'critical', 'hydrus')
        # @option opts [String] :current_status Setting this string tells the workflow service to compare the current status to this value.  If the current value does not match this value, the update is not performed
        # @return [Boolean] always true
        # Http Call
        # ==
        # The method does an HTTP PUT to the URL defined in `Dor::WF_URI`.  As an example:
        #
        #     PUT "/dor/objects/pid:123/workflows/GoogleScannedWF/convert"
        #     <process name=\"convert\" status=\"completed\" />"
        def update_workflow_status(repo, druid, workflow, process, status, opts = {})
          raise ArgumentError, "Unknown status value #{status}" unless VALID_STATUS.include?(status.downcase)

          opts = { elapsed: 0, lifecycle: nil, note: nil }.merge!(opts)
          opts[:elapsed] = opts[:elapsed].to_s
          current_status = opts.delete(:current_status)
          xml = create_process_xml({ name: process, status: status.downcase }.merge!(opts))
          uri = "#{repo}/objects/#{druid}/workflows/#{workflow}/#{process}"
          uri += "?current-status=#{current_status.downcase}" if current_status
          response = requestor.request(uri, 'put', xml, content_type: 'application/xml')

          Workflow::Response::Update.new(json: response)
        end

        #
        # Retrieves the process status of the given workflow for the given object identifier
        # @param [String] repo The repository the object resides in.  Currently recoginzes "dor" and "sdr".
        # @param [String] druid The id of the object
        # @param [String] workflow The name of the workflow
        # @param [String] process The name of the process step
        # @return [String] status for repo-workflow-process-druid
        def workflow_status(repo, druid, workflow, process)
          workflow_md = workflow_xml(repo, druid, workflow)
          doc = Nokogiri::XML(workflow_md)
          raise Dor::WorkflowException, "Unable to parse response:\n#{workflow_md}" if doc.root.nil?

          processes = doc.root.xpath("//process[@name='#{process}']")
          process = processes.max { |a, b| a.attr('version').to_i <=> b.attr('version').to_i }
          process&.attr('status')
        end

        #
        # Retrieves the raw XML for the given workflow
        # @param [String] repo The repository the object resides in.  Currently recoginzes "dor" and "sdr".
        # @param [String] druid The id of the object
        # @param [String] workflow The name of the workflow
        # @return [String] XML of the workflow
        def workflow_xml(repo, druid, workflow)
          raise ArgumentError, 'missing workflow' unless workflow

          requestor.request "#{repo}/objects/#{druid}/workflows/#{workflow}"
        end

        # Updates the status of one step in a workflow to error.
        # Returns true on success.  Caller must handle any exceptions
        #
        # @param [String] repo The repository the object resides in.  The service recoginzes "dor" and "sdr" at the moment
        # @param [String] druid The id of the object
        # @param [String] workflow The name of the workflow
        # @param [String] error_msg The error message.  Ideally, this is a brief message describing the error
        # @param [Hash] opts optional values for the workflow step
        # @option opts [String] :error_text A slot to hold more information about the error, like a full stacktrace
        # @return [Boolean] always true
        #
        # Http Call
        # ==
        # The method does an HTTP PUT to the URL defined in `Dor::WF_URI`.
        #
        #     PUT "/dor/objects/pid:123/workflows/GoogleScannedWF/convert"
        #     <process name=\"convert\" status=\"error\" />"
        def update_workflow_error_status(repo, druid, workflow, process, error_msg, opts = {})
          opts = { error_text: nil }.merge!(opts)
          xml = create_process_xml({ name: process, status: 'error', errorMessage: error_msg }.merge!(opts))
          requestor.request "#{repo}/objects/#{druid}/workflows/#{workflow}/#{process}", 'put', xml, content_type: 'application/xml'
          true
        end

        #
        # Retrieves the raw XML for all the workflows for the the given object
        # @param [String] druid The id of the object
        # @return [String] XML of the workflow
        def all_workflows_xml(druid)
          requestor.request "objects/#{druid}/workflows"
        end

        # Get workflow names into an array for given PID
        # This method only works when this gem is used in a project that is configured to connect to DOR
        #
        # @param [String] pid of druid
        # @param [String] repo repository for the object
        # @return [Array<String>] list of worklows
        # @example
        #   client.workflows('druid:sr100hp0609')
        #   => ["accessionWF", "assemblyWF", "disseminationWF"]
        def workflows(pid, repo = 'dor')
          xml_doc = Nokogiri::XML(workflow_xml(repo, pid, ''))
          xml_doc.xpath('//workflow').collect { |workflow| workflow['id'] }
        end

        # @param [String] repo repository of the object
        # @param [String] pid id of object
        # @param [String] workflow_name The name of the workflow
        # @return [Workflow::Response::Workflow]
        def workflow(repo: 'dor', pid:, workflow_name:)
          xml = workflow_xml(repo, pid, workflow_name)
          Workflow::Response::Workflow.new(xml: xml)
        end

        # Deletes a workflow from a particular repository and druid
        # @param [String] repo The repository the object resides in.  The service recoginzes "dor" and "sdr" at the moment
        # @param [String] druid The id of the object to delete the workflow from
        # @param [String] workflow The name of the workflow to be deleted
        # @return [Boolean] always true
        def delete_workflow(repo, druid, workflow)
          requestor.request "#{repo}/objects/#{druid}/workflows/#{workflow}", 'delete'
          true
        end

        private

        attr_reader :requestor

        # Adds laneId attributes to each process of workflow xml
        #
        # @param [String] lane_id to add to each process element
        # @param [String] wf_xml the workflow xml
        # @return [String] wf_xml with lane_id attributes
        def add_lane_id_to_workflow_xml(lane_id, wf_xml)
          doc = Nokogiri::XML(wf_xml)
          doc.xpath('/workflow/process').each { |proc| proc['laneId'] = lane_id }
          doc.to_xml
        end

        # @param [Hash] params
        # @return [String]
        def create_process_xml(params)
          builder = Nokogiri::XML::Builder.new do |xml|
            attrs = params.reject { |_k, v| v.nil? }
            attrs = Hash[attrs.map { |k, v| [k.to_s.camelize(:lower), v] }] # camelize all the keys in the attrs hash
            xml.process(attrs)
          end
          builder.to_xml
        end
      end
    end
  end
end