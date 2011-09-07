metadata(
  :name        => 'MySQL Cluster',
  :description => 'Agent for managing MySQL instances in a cluster',
  :author      => 'Mike Marion',
  :version     => '0.0.1',
  :url         => 'https://www.github.com/BLC/mcollective',
  :license     => '',
  :timeout     => 60
)

action 'promote', :description => 'Makes the MySQL instance a master server' do
  input :yaml_file,
    :prompt      => 'YAML file path',
    :description => 'Path to the YAML fact file',
    :type        => :string,
    :validation  => /.*/,
    :maxlength   => 0,
    :optional    => true

  output :server_id,
    :description => 'The newly assigned server ID',
    :display_as => 'Server ID'
end

action 'enslave', :description => 'Makes the MySQL instance a slave server' do
  input :yaml_file,
    :prompt      => 'YAML file path',
    :description => 'Path to the YAML fact file',
    :type        => :string,
    :validation  => /.*/,
    :maxlength   => 0,
    :optional    => true

  input :repl_user,
    :prompt      => 'Replication user',
    :description => "The username for the master's replication user",
    :type        => :string,
    :validation  => /.*/,
    :maxlength   => 0,
    :optional    => false

  input :repl_password,
    :prompt      => 'Replication password',
    :description => "The password for the master's replication user",
    :type        => :string,
    :validation  => /.*/,
    :maxlength   => 0,
    :optional    => false

  input :root_password,
    :prompt      => 'Root password',
    :description => "The password for the slave's root user, if applicable",
    :type        => :string,
    :validation  => /.*/,
    :maxlength   => 0,
    :optional    => true

  output :server_id,
    :description => 'The newly assigned server ID',
    :display_as => 'Server ID'
end
