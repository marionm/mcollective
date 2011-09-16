require 'fileutils'

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
        schedule_snapshot
        set_master_status(true)
        reply.data = "MySQL instance now the master"
      end

      #Makes the assumption that chef has given us a DB from a snapshot with MASTER_STATUS on it already
      action 'enslave' do
        status_file   = request[:master_status_file] || '/mnt/mysql/MASTER_STATUS'
        master        = request[:master_hostname]    || master_hostname
        log_file      = request[:master_log_file]    || read_property(status_file, 'master_log_file')
        log_pos       = request[:master_log_pos]     || read_property(status_file, 'master_log_pos')
        repl_user     = request[:repl_user]          || 'repl'
        repl_password = request[:repl_password]      || 'password'

        enslave(master, log_file, log_pos, repl_user, repl_password, request[:root_password])
        reload_mysql

        set_master_status(false)
        reply.data = "MySQL instance is now a slave of #{master}"
      end

      #TODO: Definitely starting to make too many assumptions in here
      def schedule_snapshot
        tmp = '/tmp/crontab'
        cron = '30 * * * * /usr/bin/take_consistent_snapshot'

        run "sudo crontab -l > #{tmp}", 'Could not dump exiting crontab'

        unless IO.read(tmp).include?(cron)
          run "echo '#{cron}' >> #{tmp}"
          run "sudo crontab #{tmp}", 'Could not update crontab'
        end

        FileUtils.rm tmp
      end

      def enslave(master, bin_log_file, bin_log_pos, repl_user, repl_password, root_password)
        set_master = <<-EOC
          change master to master_host='#{master}', master_user='#{repl_user}',
          #{"master_password='#{repl_password}'" if repl_password && !repl_password.empty?},
          master_log_file='#{bin_log_file}', master_log_pos=#{bin_log_pos};
        EOC
        mysql = "mysql -u root #{"-p#{root_password}" if root_password && !root_password.empty?} -e"

        run %{#{mysql} "slave stop"},    'Could not stop slave threads'
        run %{#{mysql} "#{set_master}"}, 'Could not set master configuration'
        run %{#{mysql} "slave start"},   'Could not start slave threads'
      end

      def set_master_status(is_master)
        yaml_facts = YAML.load_file(facts_file)
        yaml_facts['cluster_member'] = true
        yaml_facts['cluster_master'] = is_master

        File.open(facts_file, 'w') { |f| f.write YAML.dump(yaml_facts) }

        #TODO: A bit too EC2 (and factsource) specific, here
        own_hostname = `curl 169.254.169.254/latest/meta-data/public-hostname`
        #TODO: Use client library instead
        run("mco facts reload -F ec2.public_hostname=#{own_hostname}")
      end

      def master_hostname
        #TODO: Use client library instead
        out = run('mco facts ec2.public_hostname -F cluster_master=true', 'Could not query master hostname')

        out.each do |line|
          if fact = line[/\s*(.*)\s*found \d+ times/, 1]
            return fact
          end
        end
        nil
      end

      def reload_mysql
        run('sudo service mysql reload', 'Could not reload MySQL')
      end

      def facts_file
        request[:yaml_facts] || '/etc/mcollective/facts.yaml'
      end

      def read_property(file, property)
        run(%{sed -E -n 's/^#{property}="(.*)"/\\1/pi' #{file}}, "Could not read #{property} from #{file}").last.chomp
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
