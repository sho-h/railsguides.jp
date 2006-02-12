module ActionController #:nodoc:
  # Components allow you to call other actions for their rendered response while executing another action. You can either delegate
  # the entire response rendering or you can mix a partial response in with your other content.
  #
  #   class WeblogController < ActionController::Base
  #     # Performs a method and then lets hello_world output its render
  #     def delegate_action
  #       do_other_stuff_before_hello_world
  #       render_component :controller => "greeter",  :action => "hello_world", :params => { :person => "david" }
  #     end
  #   end
  #
  #   class GreeterController < ActionController::Base
  #     def hello_world
  #       render :text => "#{params[:person]} says, Hello World!"
  #     end
  #   end
  #
  # The same can be done in a view to do a partial rendering:
  # 
  #   Let's see a greeting: 
  #   <%= render_component :controller => "greeter", :action => "hello_world" %>
  #
  # It is also possible to specify the controller as a class constant, bypassing the inflector
  # code to compute the controller class at runtime:
  # 
  # <%= render_component :controller => GreeterController, :action => "hello_world" %>
  #
  # == When to use components
  #
  # Components should be used with care. They're significantly slower than simply splitting reusable parts into partials and
  # conceptually more complicated. Don't use components as a way of separating concerns inside a single application. Instead,
  # reserve components to those rare cases where you truly have reusable view and controller elements that can be employed 
  # across many applications at once.
  #
  # So to repeat: Components are a special-purpose approach that can often be replaced with better use of partials and filters.
  module Components
    def self.included(base) #:nodoc:
      base.extend(ClassMethods)
      base.send(:include, InstanceMethods)

      base.helper do
        def render_component(options) 
          @controller.send(:render_component_as_string, options)
        end
      end
    end

    module ClassMethods
      # Set the template root to be one directory behind the root dir of the controller. Examples:
      #   /code/weblog/components/admin/users_controller.rb with Admin::UsersController 
      #     will use /code/weblog/components as template root 
      #     and find templates in /code/weblog/components/admin/users/
      #
      #   /code/weblog/components/admin/parties/users_controller.rb with Admin::Parties::UsersController 
      #     will also use /code/weblog/components as template root 
      #     and find templates in /code/weblog/components/admin/parties/users/
      def uses_component_template_root
        path_of_calling_controller = File.dirname(caller[0].split(/:\d+:/).first)
        path_of_controller_root    = path_of_calling_controller.sub(/#{controller_path.split("/")[0..-2]}$/, "") # " (for ruby-mode)

        self.template_root = path_of_controller_root
      end
    end

    module InstanceMethods
      protected
        # Renders the component specified as the response for the current method
        def render_component(options) #:doc:
          component_logging(options) do
            render_text(component_response(options, true).body, response.headers["Status"])
          end
        end

        # Returns the component response as a string
        def render_component_as_string(options) #:doc:
          component_logging(options) do
            response = component_response(options, false)

            if redirected = response.redirected_to
              render_component_as_string(redirected)
            else
              response.body
            end
          end
        end

      private
        def component_response(options, reuse_response)
          klass    = component_class(options)
          request  = request_for_component(klass.controller_name, options)
          response = reuse_response ? @response : @response.dup
        
          klass.process(request, response, self)
        end
        
        # determine the controller class for the component request
        def component_class(options)
          if controller = options[:controller]
            controller.is_a?(Class) ? controller : "#{controller.camelize}Controller".constantize
          else
            self.class
          end
        end
        
        # Create a new request object based on the current request.
        # The new request inherits the session from the current request,
        # bypassing any session options set for the component controller's class
        def request_for_component(controller_name, options)
          request         = @request.dup
          request.session = @request.session
        
          request.instance_variable_set(
            :@parameters,
            (options[:params] || {}).with_indifferent_access.regular_update(
              "controller" => controller_name, "action" => options[:action], "id" => options[:id]
            )
          )
          
          request
         end

         def component_logging(options)
           if logger
             logger.info "Start rendering component (#{options.inspect}): "
             result = yield
             logger.info "\n\nEnd of component rendering"
             result
           else
             yield
           end
         end
    end
  end
end
