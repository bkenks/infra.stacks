package kv

#Name:    =~"^[a-z][a-z0-9]*(-[a-z0-9]+)*$"
_project: "kv" & #Name
name:     _project

#Service: {
	image:          string
	container_name: string
	restart:        *"unless-stopped" | "no" | "always"

	ports?: [...string]
	networks?: [...string]
	volumes?: [...string]
}

services: [N=string]: #Service & {
	_key:           N & #Name
	container_name: "\(_project)-\(_key)"
}

networks: [N=string]: {
	_key: N & #Name
	name: "\(_project)-\(_key)"
}

volumes: [N=string]: {
	_key: N & #Name
	name: "\(_project)-\(_key)"
}

services: web: {
	image: "nginx:1.27"
	ports: ["8080:80"]
}
services: db: image: "postgres:17"
networks: backend: {}
volumes: "pg-data": {}
