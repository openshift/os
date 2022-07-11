package fixtures

import _ "embed"

//go:embed Dockerfile
var Dockerfile string

//go:embed hello-world.go.fixture
var HelloWorldSrc string

//go:embed hello-world.service
var HelloWorldService string
