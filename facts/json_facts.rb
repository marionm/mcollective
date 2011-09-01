module MCollective
  module Facts

    begin
      require 'yajl'
    rescue
      raise 'The json fact source requires the yajl-ruby gem'
    end

    #Uses JSON files as fact sources.                                     
    #Based off of the MCollective YAML fact plugin.                      
    #Set the server config plugin.json value to a file,                 
    #or multipe files separated by a colon.    
    class Json_facts < Base
      def initialize
        @json_file_mtimes = {}
        super
      end

      def load_facts_from_source
        fact_files = config.pluginconf["json"]
        raise 'Must set plugin.json to use json fact source' unless fact_files

        {}.tap do |facts|
          fact_files.split(':').each do |file|
            begin
              json = IO.read file
              facts.merge!(Yajl.load(json))
            rescue Exception => e
              Log.error("Failed to load JSON facts from #{file}: #{e.class}: #{e}")
            end
          end
        end
      end

      # force fact reloads when the mtime on the yaml file change
      def force_reload?
        fact_files = config.pluginconf["json"].split(":")
        fact_files.each do |file|
          @json_file_mtimes[file] ||= File.stat(file).mtime
          mtime = File.stat(file).mtime

          if mtime > @json_file_mtimes[file]
            Log.debug("Forcing fact reload due to age of #{file}")
            @json_file_mtimes[file] = mtime
            return true
          end
        end

        false
      end

      private

      def config
        @config ||= Config.instance
      end
    end

  end
end
