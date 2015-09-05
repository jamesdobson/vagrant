require "log4r"
#require "lockfile"

module VagrantPlugins
  module ProviderVirtualBox
    module Action
      class CreateClone
        def initialize(app, env)
          @app = app
          @logger = Log4r::Logger.new("vagrant::action::vm::clone")
        end

        def call(env)
          @logger.info("Creating linked clone from master '#{env[:master_id]}'")
        
          env[:ui].info I18n.t("vagrant.actions.vm.clone.creating", name: env[:machine].box.name)
          env[:machine].id = env[:machine].provider.driver.clonevm(env[:master_id], env[:machine].box.name, "base") do |progress|
            env[:ui].clear_line
            env[:ui].report_progress(progress, 100, false)
          end

          # Clear the line one last time since the progress meter doesn't disappear immediately.
          env[:ui].clear_line

          # Flag as erroneous and return if clone failed
          raise Vagrant::Errors::VMCloneFailure if !env[:machine].id

          # Continue
          @app.call(env)
        end

        def recover(env)
          if env[:machine].state.id != :not_created
            return if env["vagrant.error"].is_a?(Vagrant::Errors::VagrantError)

            # If we're not supposed to destroy on error then just return
            return if !env[:destroy_on_error]

            # Interrupted, destroy the VM. We note that we don't want to
            # validate the configuration here, and we don't want to confirm
            # we want to destroy.
            destroy_env = env.clone
            destroy_env[:config_validate] = false
            destroy_env[:force_confirm_destroy] = true
            env[:action_runner].run(Action.action_destroy, destroy_env)
          end
        end
      end
    end
  end
end
