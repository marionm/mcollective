This is a collection of agents and plugins for MCollective.

To install to a server, just clone on top of your server config's libdir directory.

## Fact source plugins

#### Multisource

Allows the use of multipe fact sources at once.

*server.cfg*
```
# Set the factsource
factsource = multisource

# Set the sources to use
# Fact conflicts are won by later sources
plugin.factsources = opscodeohai:yaml

# Finish configuring the individual plugins used
plugin.yaml = /etc/mcollective/facts.yaml
```

#### JSON

Can use JSON files as fact sources. Requires yajl-ruby gem.

*server.cfg*
```
# Set the factsource
factsource = json

# Point to a single JSON file
plugin.json = /etc/mcollective/facts.json

# Or, point to multipe JSON files
# Fact conflicts are won by later files
plugin.json = /etc/mcollective/facts.json:/etc/chef/node.json

```
