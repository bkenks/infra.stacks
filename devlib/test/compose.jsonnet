local project = { local project = self,
  name: "myproject",
  networks: {
    mynet: { name: 'mynet' }
  },
  volumes: {
    myvol: { name: 'myvol'}
  },
  services: {
    app: {
      image: 'app/myapp:latest',
      restart: 'unless-stopped',
      networks: [ project.networks.mynet.name ],
    }
  }
};

std.manifestYamlDoc(project, indent_array_in_object=true, quote_keys=true)