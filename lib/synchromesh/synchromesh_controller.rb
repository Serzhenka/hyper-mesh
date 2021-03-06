module ReactiveRecord
  ::HyperMesh::Engine.routes.append do
    HyperMesh.initialize_policies

    module ::WebConsole
      class Middleware
      private
        def acceptable_content_type?(headers)
          Mime::Type.parse(headers['Content-Type'] || '').first == Mime[:html]
        end
      end
    end if defined? ::WebConsole::Middleware

    module ::Rails
      module Rack
        class Logger < ActiveSupport::LogSubscriber
          unless method_defined? :pre_synchromesh_call
            alias pre_synchromesh_call call
            def call(env)
              if !HyperMesh.opts[:noisy] && env['HTTP_X_SYNCHROMESH_SILENT_REQUEST']
                Rails.logger.silence do
                  pre_synchromesh_call(env)
                end
              else
                pre_synchromesh_call(env)
              end
            end
          end
        end
      end
    end if defined?(::Rails::Rack::Logger)

    class HyperMeshController < ::ApplicationController

      protect_from_forgery except: [:console_update]

      def client_id
        params[:client_id]
      end

      before_action do
        session.delete 'synchromesh-dummy-init' unless session.id
      end

      def channels(user = acting_user, session_id = session.id)
        HyperMesh::AutoConnect.channels(session_id, user)
      end

      def can_connect?(channel, user = acting_user)
        HyperMesh::InternalPolicy.regulate_connection(
          user,
          HyperMesh::InternalPolicy.channel_to_string(channel)
        )
        true
      rescue
        nil
      end

      def view_permitted?(model, attr, user = acting_user)
        !!model.check_permission_with_acting_user(user, :view_permitted?, attr)
      rescue
        nil
      end

      def viewable_attributes(model, user = acting_user)
        model.attributes.select { |attr| view_permitted?(model, attr, user) }
      end

      [:create, :update, :destroy].each do |op|
        define_method "#{op}_permitted?" do |model, user = acting_user|
          begin
            !!model.check_permission_with_acting_user(user, "#{op}_permitted?".to_sym)
          rescue
            nil
          end
        end
      end

      def debug_console
        if Rails.env.development?
          render inline: "<style>div#console {height: 100% !important;}</style>\n".html_safe
          #  "<div>additional helper methods: channels, can_connect? "\
          #  "viewable_attributes, view_permitted?, create_permitted?, "\
          #  "update_permitted? and destroy_permitted?</div>\n".html_safe
          console
        else
          head :unauthorized
        end
      end

      def subscribe
        HyperMesh::InternalPolicy.regulate_connection(try(:acting_user), params[:channel])
        root_path = request.original_url.gsub(/synchromesh-subscribe.*$/, '')
        HyperMesh::Connection.open(params[:channel], client_id, root_path)
        head :ok
      rescue Exception
        head :unauthorized
      end

      def read
        root_path = request.original_url.gsub(/synchromesh-read.*$/, '')
        data = HyperMesh::Connection.read(client_id, root_path)
        render json: data
      end

      def pusher_auth
        channel = params[:channel_name].gsub(/^#{Regexp.quote(HyperMesh.channel)}\-/,'')
        HyperMesh::InternalPolicy.regulate_connection(acting_user, channel)
        response = HyperMesh.pusher.authenticate(params[:channel_name], params[:socket_id])
        render json: response
      rescue Exception => e
        head :unauthorized
      end

      def action_cable_auth
        channel = params[:channel_name].gsub(/^#{Regexp.quote(HyperMesh.channel)}\-/,'')
        HyperMesh::InternalPolicy.regulate_connection(acting_user, channel)
        salt = SecureRandom.hex
        authorization = HyperMesh.authorization(salt, channel, client_id)
        render json: {authorization: authorization, salt: salt}
      rescue Exception
        head :unauthorized
      end

      def connect_to_transport
        root_path = request.original_url.gsub(/synchromesh-connect-to-transport.*$/, '')
        render json: HyperMesh::Connection.connect_to_transport(params[:channel], client_id, root_path)
      end

      def console_update
        authorization = HyperMesh.authorization(params[:salt], params[:channel], params[:data][1][:broadcast_id]) #params[:data].to_json)
        return head :unauthorized if authorization != params[:authorization]
        HyperMesh::Connection.send_to_channel(params[:channel], params[:data])
        head :no_content
      rescue
        head :unauthorized
      end

      def server_up
        head :no_content
      end

    end unless defined? HyperMeshController

    match 'synchromesh-subscribe/:client_id/:channel',
          to: 'hyper_mesh#subscribe', via: :get
    match 'synchromesh-read/:client_id',
          to: 'hyper_mesh#read', via: :get
    match 'synchromesh-pusher-auth',
          to: 'hyper_mesh#pusher_auth', via: :post
    match 'synchromesh-action-cable-auth/:client_id/:channel_name',
          to: 'hyper_mesh#action_cable_auth', via: :post
    match 'synchromesh-connect-to-transport/:client_id/:channel',
          to: 'hyper_mesh#connect_to_transport', via: :get
    match 'console',
          to: 'hyper_mesh#debug_console', via: :get
    match 'console_update',
          to: 'hyper_mesh#console_update', via: :post
    match 'server_up',
          to: 'hyper_mesh#server_up', via: :get
  end
end
