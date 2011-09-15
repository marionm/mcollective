module MCollective
  module Agent
    class Mysql_cluster < RPC::Agent
      metadata(
        :name        => 'MySQL Cluster',
        :description => 'Agent for managing MySQL instances in a cluster',
        :author      => 'Mike Marion',
        :version     => '0.0.2',
        :url         => 'https://www.github.com/BLC/mcollective',
        :license     => '',
        :timeout     => 60
      )

      #TODO: This will eventually need to do something a bit more interesting, like promoting
      #      a slave to become a master through reconfiguration of all other slaves
      action 'promote' do
        set_master_status(true)
        reply.data = "MySQL instance now the master"
      end

      #Makes the assumption that chef has given us a DB from a snapshot with MASTER_STATUS on it already
      action 'enslave' do
        validate :repl_user, String

        status_file = request[:master_status_file] || '/mnt/mysql/MASTER_STATUS'
        log_file    = request[:master_log_file]    || read_property(status_file, 'master_log_file')
        log_pos     = request[:master_log_pos]     || read_property(status_file, 'master_log_pos')
        master      = request[:master_hostname]    || master_hostname

        enslave(master, log_file, log_pos, request[:repl_user], request[:repl_password], request[:root_password])
        reload_mysql

        set_master_status(false)
        reply.data = "MySQL instance is now a slave of #{master}"
      end

      def enslave(master, bin_log_file, bin_log_pos, repl_user, repl_password, root_password)
        mysql = "mysql -u root #{"-p#{root_password}" if root_password}"

        run "#{mysql} -e ''", 'Could not connect to DB instance'
        run "#{mysql} -e 'slave stop'", 'Could not stop slave threads'

        command = "change master to "
        command << "master_host='#{master}' "
        command << "master_user='#{repl_user}' "
        command << "master_password='#{repl_password}' " if repl_password
        command << "master_log_file='#{log_file}' "
        command << "master_log_pos=#{log_pos};"

        run %{#{mysql} -e "#{command}"}, 'Could not set master configuration'
        run "#{mysql} -e 'slave start'", 'Could not start slave threads'
      end

      def reload_mysql
        run('sudo service mysql reload', 'Could not reload MySQL')
      end

      def master_hostname
        #TODO: Use client library instead
        out = run('mco facts ec2.public_hostname -W "role.mysql_server cluster_master=true"', 'Could not query master hostname')

        out.each do |line|
          if fact = extract_fact(line)
            return fact
          end
        end
        nil
      end

      def read_property(file, property)
        run(%{sed -E -n 's/^#{property}="(.*)"/\1/pi' #{file}}, "Could not read #{property} from #{file}").chomp
      end

      def extract_fact(line)
        line[/\s*(.*)\s*found \d+ times/, 1]
      end

      def facts_file
        request[:yaml_facts] || '/etc/mcollective/facts.yaml'
      end

      def set_master_status(master)
        yaml_facts = YAML.load_file(facts_file)

        #TODO: Can you match (or anti-match) non-set facts?
        facts = { :cluster_member => true, :cluster_master => master }
        facts.each do |fact, value|
          yaml_facts[fact.to_s] = value
        end

        File.open(facts_file, 'w') { |f| f.write YAML.dump(yaml_facts) }

        #TODO: A bit too EC2 (and factsource) specific, here
        own_hostname = `curl 169.254.169.254/latest/meta-data/public-hostname`
        #TODO: Use client library instead
        run("mco facts reload -F ec2.public_hostname=#{own_hostname}")
      end

      def run(command, failure_message = nil)
        out = []
        err = ''
        status = super(command, :stdout => out, :stderr => err)
        if failure_message
          if status != 0
            reply.fail!("#{failure_message}: #{err}")
          else
            out
          end
        else
          [status, out, err]
        end
      end
    end
  end
end
