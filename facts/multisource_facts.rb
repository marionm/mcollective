module MCollective
  module Facts

    #Set the server config plugin.sources to a colon-separated list
    #Facts conflicts will give later sources priority over earlier sources
    class Multisource_facts < Base
      def load_facts_from_source
        sources = Config.instance.pluginconf['factsources']
        raise 'Must set plugin.sources to use multisource fact source' unless sources

        {}.tap do |facts|
          sources.split(':').each do |source|
            facts.merge!(get_plugin(source).load_facts_from_source)
          end
        end
      end

      private

      def get_plugin(source)
        source_class = "#{source.capitalize}_facts"
        PluginManager.loadclass("MCollective::Facts::#{source_class}")
        Facts.module_eval("#{source_class}").new
      end
    end

    class Base
      #The default inherited behavior thries to register the plugin with
      #PluginManager, which raises an error if the same plugin types are
      #registered multiple times. Once Multisource_facts is loaded, remove
      #this functionality to allow other fact plugins to be required.
      def self.inherited(klass); end
    end

  end
end

