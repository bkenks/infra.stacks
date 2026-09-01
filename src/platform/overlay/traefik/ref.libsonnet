{
  config:: { local thisConfig = self,
    dirName:: "config",

    traefik:: { local thisTraefik = self,
      name:: "traefik",
      fileExtension:: "yaml",
      fullFileName:: self.name + "." + self.fileExtension,
      path:: {
        relative:: "./" + thisConfig.dirName + "/" + thisTraefik.fullFileName
      }
    }
  }
}