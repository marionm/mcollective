module MCollective
  module Agent
    class Mysql_cluster < RPC::Agent
      metadata(
        :name        => 'MySQL Cluster',
        :description => 'Agent for managing MySQL instances in a cluster',
        :author      => 'Mike Marion',
        :version     => '0.0.1',
        :url         => 'https://www.github.com/BLC/mcollective',
        :license     => '',
        :timeout     => 60
      )

      action 'promote' do
        validate :yaml_facts, String

        server_id = unique_server_id

        set_server_id(server_id)
        enable_bin_log
        reload_mysql

        set_facts(request[:yaml_facts], server_id, true)

        reply.data = "New master server ID: #{server_id}"
      end

      action 'enslave' do
        validate :yaml_facts, String
        validate :repl_user, String
        validate :repl_password, String

        server_id = unique_server_id

        set_server_id(server_id)
        enslave(request[:repl_user], request[:repl_password], request[:root_password])
        reload_mysql

        set_facts(request[:yaml_facts], server_id, false)

        reply.data = "New slave server ID: #{server_id}"
      end

      #TODO: How to do discovery directly from within an agent?
      #TODO: Can server ID generation (and therefore this entire thing) be pushed into chef?
      #      All unique things about the instance seem to form too large of an integer ID, even after
      #      applying some non-colliding operation, so discovery would have to be done mid Chef run.
      def unique_server_id
        status, out, err = run('mco facts mysql_server_id -W "role.mysql_server cluster_member=true"')
        reply.fail! "Could not query environment: #{err}" unless status == 0

        existing_ids = out.map! { |line| extract_fact(line).to_i }
        existing_ids.delete(nil)
        existing_ids.sort

        id = 1
        while existing_id = existing_ids.shift
          return id if existing_id != id
          id += 1
        end
        id
      end

      def set_server_id(server_id)
        command = 's/^\s*#*\s*\(server-id\)\s*=.*/\1 = ' + server_id.to_s + '/'
        status, out, err = run(%{sudo sed -i "#{command}" /etc/mysql/my.cnf})
        reply.fail! "Could not set server id: #{err}" unless status == 0
      end

      def enable_bin_log
        command = 's/^\s*#*\s*\(log_bin\s*=.*\)/\1/'
        status, out, err = run(%{sudo sed -i "#{command}" /etc/mysql/my.cnf})
        reply.fail! "Could not enable bin log: #{err}" unless status == 0
      end

      def enslave(repl_user, repl_password, root_password)
        status, out, err = run("mysql -u root #{"-p#{root_password}" if root_password} -e ''")
        reply.fail! "Could not connect to DB instance: #{err}" unless status == 0

        command = "change master to "
        command << "master_host='#{master_hostname}' "
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

      def set_facts(facts_file, server_id, master)
        yaml_facts = YAML.load_file(facts_file)

        facts = { :mysql_server_id => server_id, :cluster_member => true, :cluster_master => master }
        facts.each do |fact, value|
          yaml_facts[fact.to_s] = value
        end

        File.open(facts_file, 'w') { |f| f.write YAML.dump(yaml_facts) }

        #TODO: A bit too EC2 (and factsource) specific, here
        own_hostname = `curl 169.254.169.254/latest/meta-data/public-hostname`
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
