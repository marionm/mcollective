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

      action 'promote' do
        validate :yaml_facts, String

        enable_bin_log
        reload_mysql

        set_facts(request[:yaml_facts], true)

        reply.data = "MySQL instance now able to be a master"
      end

      action 'enslave' do
        validate :yaml_facts, String
        validate :repl_user, String
        validate :repl_password, String

        master = master_hostname
        enslave(request[:repl_user], request[:repl_password], request[:root_password])
        reload_mysql

        set_facts(request[:yaml_facts], false)

        reply.data = "MySQL instance is now a slave of #{master}"
      end

      def enable_bin_log
        command = 's/^\s*#*\s*\(log_bin\s*=.*\)/\1/'
        status, out, err = run(%{sudo sed -i "#{command}" /etc/mysql/my.cnf})
        reply.fail! "Could not enable bin log: #{err}" unless status == 0
      end

      def enslave(master, repl_user, repl_password, root_password)
        status, out, err = run("mysql -u root #{"-p#{root_password}" if root_password} -e ''")
        reply.fail! "Could not connect to DB instance: #{err}" unless status == 0

        command = "change master to "
        command << "master_host='#{master}' "
        command << "master_user='#{repl_user}' "
        command << "master_password='#{repl_password}' "
        command << "master_log_file='#{}' "
        command << "master_log_pos=#{};"

        status, out, err = run(%{mysql -u root #{"-p#{root_password}" if root_password} -e "#{command}"})
        reply.fail! "Could not set master configuration: #{err}" unless status == 0
      end

      def reload_mysql
        status, out, err = run('sudo service mysql reload')
        reply.fail! "Could not reload MySQL config: #{err}" unless status == 0
      end

      def master_hostname
        #TODO: Use client library instead
        status, out, err = run('mco facts ec2.public_hostname -W "role.mysql_server cluster_master=true"')

        out.each do |line|
          if fact = extract_fact(line)
            return fact
          end
        end
        nil
      end

      def extract_fact(line)
        line[/\s*(.*)\s*found \d+ times/, 1]
      end

      def set_facts(facts_file, master)
        yaml_facts = YAML.load_file(facts_file)

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

      def run(command)
        out = []
        err = ''
        status = super(command, :stdout => out, :stderr => err)
        [status, out, err]
      end
    end
  end
end
