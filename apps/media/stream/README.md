<h1 align="center">
  <br>
  <!-- <a href="http://www.amitmerchant.com/electron-markdownify"><img src="https://raw.githubusercontent.com/amitmerchant1990/electron-markdownify/master/app/img/markdownify.png" alt="Markdownify" width="200"></a> -->
  <br>
  Streaming
  <br>
</h1>

<p align="center">
  <a href="#services-included">Services Included</a> •
  <a href="#prerequisite-setup">Prerequisite Setup</a> •
  <a href="#service-setup">Service Setup</a>
</p>

## Services Included

* Plex
* Seer (Overseerr's successor — request management)
* Prowlarr
* Bazarr
* sabNZBD
* Radarr
* Sonarr
* Configarr — config-as-code for Sonarr/Radarr quality profiles (one-shot job, no UI)
* Decluttarr — auto-clears failed/stalled/orphaned downloads from the queues (long-running, no UI)

## Prerequisite Setup

### 1. Setup Directories for "stream" Docker/Dockge stack

Here is the directory tree that you will be setting up for the "stream" stack

```
~/
└── docker_volumes/
    └── stream/
        ├── config/
        │   ├── bazarr
        │   ├── seerr
        │   ├── plex
        │   ├── prowlarr
        │   ├── radarr
        │   ├── sabnzbd
        │   └── sonarr
        └── shared/
            ├── media/
            │   ├── movies
            │   └── series
            └── usenet/
                ├── incomplete
                └── complete/
                    ├── series
                    └── movies
```

This base path is `DOCKER_VOLUMES/stream/` — set `DOCKER_VOLUMES` per
[`setup.md`](./setup.md). The per-app `config/` dirs and the `shared/` tree are
bind-mounted by `compose/stack.yaml`.

> Configarr also needs a writable `${DOCKER_VOLUMES}/stream/configarr/repos`
> cache dir (it clones the TRaSH-guide repo there). Its actual *config* —
> `configarr/config.yml` — lives **in this repo** (mounted read-only), not on the
> host; that's the point of config-as-code. See [`setup.md`](./setup.md) for the
> exact host paths.

### 2. Deploy the stack (Komodo)

This stack now follows the `template.stack` convention (single `compose.yaml`
include → `compose/stack.yaml`) and deploys as **one Komodo stack** — see
[`setup.md`](./setup.md) for the full layout, the required `DOCKER_VOLUMES`, and
the Traefik hostnames. Point a Komodo stack at this repo's `compose.yaml`,
set `DOCKER_VOLUMES`, deploy.

> The HTTP services below are reached at `<service>.homektb.com` (Traefik,
> tailnet/LAN) — e.g. `sonarr.homektb.com`. Plex stays on host networking at
> `:32400`. Where the steps say `<your-server-ip>:<port>`, the Traefik hostname
> works too.

## Service Setup

### 1. SABnzbd

1. Access SABnzbd in a browser (<your-server-ip>:8080)

2. Configure the fields according to what your Usenet providers gives you.

3. Click Test Server to make sure you entered the fields correctly, click Next, click Go to SABnzbd, click the top-right gear icon, click General.

4. Under Security, set a SABnzbd Username and a SABnzbd Password and click the Save Changes button bellow, click OK in the popup and wait for the restart to complete. You can now login and go to the settings again.
   
   - Note If SABnzbd fails to restart automatically, restart it manually using sudo `docker compose restart sabnzbd`.

5. Go to the Folders tab and configure the Completed Download Folder to /data/usenet, save changes.

6. Go to the Catagories tab and remove all the default categories using the trash bin icons on the right. Configure the default category's Folder/Path to `other`, save. Add a new category named library with Folder/Path set to `library`, click Add.

7. Go to the Switches tab and tick Direct Unpack under Queue, save.

🎉 You're done with SABnzbd 🎉

### 2. *ARRs

Access each *ARR in a browser (<your-server-ip>:9696). You can find the ports in Dockge or using `docker ps -a`

#### Prowlarr

1. Select Forms (Login Page), set a Username and a Password and click Save.

2. Click Add indexer on the top panel (yours is NZBGeek), search for the Usenet or torrent indexers you want to add, fill the required fields, click on Test then Save if successful.

3. On the left side panel click Settings, then UI, then you may want to change some formats under the Dates category and click Save on the top panel.

4. On the left side panel click Settings, then Apps, then the + icon.

> **This is the step that makes Prowlarr worth running.** Wiring an *arr as an
> "App" here means Prowlarr **pushes every indexer (and any future indexer
> change) to that *arr automatically** — you configure indexers once, in
> Prowlarr, instead of per-app. Add Sonarr and Radarr (and Lidarr/Readarr if you
> run them).
>
> **Use internal container DNS, not the server IP.** All these services share the
> `default` compose network, so they resolve each other by service name. That's
> more robust than an IP and survives host moves:
>
> | Field              | Value                       |
> |--------------------|-----------------------------|
> | Prowlarr Server    | `http://prowlarr:9696`      |
> | Sonarr Server      | `http://sonarr:8989`        |
> | Radarr Server      | `http://radarr:7878`        |

**The following steps should be done for each arr app in Prowlarr**

1. Set Sync Level to Full Sync.

2. In the Prowlarr Server field enter `http://prowlarr:9696` (internal DNS — see the tip above).

3. In the *arr Server field enter `http://<service>:<port>` — `http://sonarr:8989` for Sonarr, `http://radarr:7878` for Radarr (8686 Lidarr, 8787 Readarr).

4. Access the *arr app using a browser, on the left side panel click Settings, then General, then copy the API Key under Security. Paste it in the ApiKey field, press Save.

Once this is done, every indexer you've added in Prowlarr appears in Sonarr/Radarr automatically, and stays in sync.

#### Bazarr

Access Bazarr in a browser (<your-server-ip>:6767).

The following is the setup you will need to do per tab in the left navigation bar.

> **General**
> On the left side panel click Settings, then General, set the Authentication field to Form, fill the Username and Password fields and click Save on the top panel.

> **Languages**
> On the left side panel click Settings, then Languages, in the Languages Filter field select the language(s) you want to request for subtitles and click Add New Profile.
> 
> Write Main in the Name field. Click on Add Language n times while n being the number of languages your want your subtitles in. In the second row of the table make sure each line have a unique language. Click Save, click Save on the top panel.

> **Providers**
> On the left side panel click Settings, then Providers, then click on +. Most subtitles providers require login-in, therefore you will most likely need to first create an account on the provider website and then fill your Username and Password of that provider the fields you will get after selecting a provider.
> 
> I personally recommend to add at least OpenSubtitles.com and then to scroll though the list to see if some providers may provide you with subtitles in your native language.
> 
> Click on Save each time and on + again if you want to add another one.
> 
> Click on the top panel Save button.
> 
> Sonarr & Radarr link
> On the left side panel click Settings, then Sonarr, then enable it.
> 
> Fill the Address field with <your-server-ip>.
> 
> Note If you set up the subdomains and HTTPS you should fill the Address field with sonarr.example.org, the Port field with 443 and enable SSL.
> 
> Access the Sonarr app using a browser, on the left side panel click Settings, then General, then copy the API Key under Security. Paste it in the API Key field.
> 
> Press Test and then the Save button on the top panel.
> 
> On the left side panel click Settings, then Radarr, then enable it and then perform the same last actions but with Radarr.

🎉 You're done with Bazarr 🎉

#### Other *ARR apps

These steps will show the setup for all Sonarr, Radarr, Lidarr and Readarr apps at the same time because they are very similar. You are free to skip either Lidarr and/or Readarr if you don't want to download music/audios and/or eBooks respectively.

Access *arr in a browser (<your-server-ip>:<the-*arr-app-port>), replace <the-*arr-app-port> by 8989 for Sonarr, by 7878 for Radarr, by 8686 for Lidarr and by 8787 for Readarr.

> **Language**
> *Sonarr and Radarr Specific:*
> On the left side panel click Settings, then Profiles, then click on English under Language Profiles. You may want to add more languages then English, tick the one you want, change the Name field to Main and click Save.

> **Quality**
> *Sonarr and Radarr Specific:*
> 
> On the left side panel click Settings, then Quality, then make sure the gear icon on the top is named Hide Advanced. In my case I watch movies and series in 1080p, so for each quality name that contains 1080, I will set its corresponding Max field to something like 80. This way, *arr will only download files with a maximum ratio of 4.7 GB per hour. Otherwise your server's disk will get full quickly. Radarr requires you to set a Preferred value too. Click Save.
> 
> *Usenet Specific:*
> Click on SABnzbd, write SABnzbd in the Name field. Write <your-server-ip> in the Host field and 8080 in the Port field.
> 
> Access SABnzbd in a new tab. Click on the top-right gear icon, then the General tab and copy the API Key under Security. Paste this key in the API Key field.
> 
> Fill the Username and Password fields with the same one you used in SABnzbd.
> 
> Write library in the Category field and press Save.

> **General**
> On the left side panel click Settings, then UI, then you may want to change some formats under the Calendar and Dates categories and click Save on the top panel.
> 
> On the left side panel click Settings, then General, set the Authentication field to Form (Login Page), fill the Username and Password fields and click Save on the top panel. If it asks, clik on Restart Now.

🎉 You're done with one *arr app 🎉

Now do this again for each *arr app :).

🎉 You're done with every *arr app 🎉

#### Configarr (quality profiles + custom formats as code)

Configarr replaces the manual **Quality** tuning above with config-as-code. It's a
one-shot container: on every stack deploy it reads [`configarr/config.yml`](./configarr/config.yml)
and syncs the declared [TRaSH-guide](https://trash-guides.info) quality
definitions, quality profiles, and custom formats into Sonarr and Radarr, then
exits. It only manages **quality scoring** — not indexers (that's Prowlarr),
download clients, root folders, or media.

**One-time prerequisite — store the API keys in Infisical.** Configarr needs each
*arr's API key (Sonarr/Radarr → Settings → General → Security → API Key). They are
secrets, so they live in Infisical, not in this repo:

- Store them in Infisical under the **`/stream`** folder, **prod** environment:
  - `SONARR_API_KEY`
  - `RADARR_API_KEY`
- The infisical-agent renders them to `/dev/shm/stream.env` on the host, and
  `compose.yaml` feeds them into the Configarr container. See
  [`setup.md`](./setup.md) for the agent-template wiring (one block in the host's
  infisical-agent config).

**Running it.** It runs automatically as part of `Deploy` in Komodo. Because it's
a one-shot job, after a successful run it shows as **exited (0)** in Komodo —
that's expected, not a failure. To re-apply after editing the config, redeploy
the stack (or restart just the `configarr` service). Check its container logs to
see what it changed.

**Editing the config.** Edit [`configarr/config.yml`](./configarr/config.yml),
commit, and redeploy. It ships with the TRaSH **1080p WEB** profile for Sonarr and
the **HD Bluray + WEB** profile for Radarr; comments in the file show how to switch
to 4K/2160p. Template names come from the
[recyclarr template list](https://recyclarr.dev/wiki/) (Configarr uses the same set).

🎉 You're done with Configarr 🎉

### Plex

1. Stop the **Plex** container

2. Go to plex.tv/claim and paste the code to your PLEX_CLAIM variable.

3. Restart container

4. Access Plex in a browser (<your-server-ip>:32400).

5. Log in with your Plex account.

6. Click GOT IT!, close the popup, give your library a nice name.

7. Click ADD LIBRARY, then Movies, then NEXT, then BROWSE FOR MEDIA FOLDER, browse to /data/media/movies, click ADD LIBRARY.

8. Click ADD LIBRARY, then TV Shows, write Series in the Name field, then click on NEXT, then BROWSE FOR MEDIA FOLDER, browse to /data/media/series, click ADD LIBRARY.

9. Click ADD LIBRARY, then TV Shows, write Music in the Name field, then click on NEXT, then BROWSE FOR MEDIA FOLDER, browse to /data/media/music, click ADD LIBRARY.

10. Click on NEXT then DONE.

11. Click the top-right wrench icon.

12. On the left side panel, scroll down and click on Library under Settings. Tick Scan my library automatically and Run a partial scan when changes are detected. Set the Generate video preview thumbnails and Generate chapter thumbnails fields to as a scheduled task and when media is added and click on Save Changes.

13. On the left side panel, click on Quality under Plex Web, here you may want to set a different default Video quality, 10 Mbps, 1080p as for myself.

14. f you want to be able to access your Plex library directly access Plex via plex.tv you need to allow the port 32400 in your firewall and router too if using something like Oracle Cloud. Then go Remote Access tab under Settings, tick Manually specify public port, set it to 32400 and click Apply, if you configured your router/firewall correctly it should say Fully accessible outside your network.

15. Ensure you enable hardware acceleration/transcoding

🎉 You're done with Plex 🎉

#### Seer

> Migrated from Overseerr — the existing config/database carries over automatically
> on first boot, so an established instance needs no re-setup. The steps below are
> for a **fresh** install. UI is reached at `seerr.homektb.com`.

1. Access Seer in a browser (<your-server-ip>:5055).

2. Sign in with Plex.

3. Click the refresh icon on the right, wait and select one entry, you should prioritize [secure] then [local]. Click on Save changes, select Movies and Series and click on Continue.
   
   *Radarr & Sonarr Specific:*
   Click on Add Radarr Server, tick Default server, write Radarr in the Server name field, write <your-server-ip> in the Hostname or IP Address field.
   
   Access the Radarr app using a browser, on the left side panel click Settings, then General, then copy the API Key under Security. Paste it in the API Key field.
   
   Click the yellow Test button. Select your desired quality profile, select the only root folder available.
   
   *Sonarr Specific:*
   Select the only language profile available, select your desired anime quality profile, select the only root folder available, select the only anime language profile available and tick Season Folders.
   
   Tick Enable Scan and click Add Server.
   
   Perform the same last actions but with Sonarr now.

4. Click Finish Setup.

5. Click Settings, the Users tab, go down a bit and tick Auto-Approve, then tick Auto-Request and click Save Changes.

🎉 You're done with Seer 🎉