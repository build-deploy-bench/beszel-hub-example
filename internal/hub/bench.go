package hub

// Benchmark support for build-deploy-bench. Not part of upstream Beszel; see BENCH.md.

import (
	"fmt"
	"net/http"
	"os"
	"strings"
	"time"

	"github.com/pocketbase/pocketbase/core"
)

// benchCommit is the commit that was built. bench/build.sh sets it with -ldflags -X.
var benchCommit = "unknown"

// benchMark prints a `::bench::<name> <epoch ms>` marker that the benchmark parsers read from the runtime logs.
func benchMark(name string) {
	fmt.Printf("::bench::%s %d\n", name, time.Now().UnixMilli())
}

// BenchArgs prints the start marker and returns the command line to run. When PORT is set and `serve` has no --http
// flag, it adds --http=0.0.0.0:$PORT, so the hub listens where each provider routes traffic. The image has no shell
// that could expand $PORT in CMD.
func BenchArgs(args []string) []string {
	benchMark("start")
	port := os.Getenv("PORT")
	if port == "" || len(args) < 2 || args[1] != "serve" {
		return args
	}
	for _, a := range args[2:] {
		if a == "--http" || strings.HasPrefix(a, "--http=") {
			return args
		}
	}
	return append(args, "--http=0.0.0.0:"+port)
}

// benchServe adds GET /version and prints the listening marker once PocketBase has bound the listen socket.
// PocketBase binds the socket in the last handler of the OnServe chain, so it is bound when e.Next() returns.
func benchServe(e *core.ServeEvent) error {
	e.Router.GET("/version", func(re *core.RequestEvent) error {
		return re.JSON(http.StatusOK, map[string]string{
			"commit":     benchCommit,
			"run":        benchEnv("BENCH_RUN_ID"),
			"deployment": benchEnv("RAILWAY_DEPLOYMENT_ID"),
		})
	})
	if err := e.Next(); err != nil {
		return err
	}
	benchMark("listening")
	return nil
}

func benchEnv(name string) string {
	if v := os.Getenv(name); v != "" {
		return v
	}
	return "unknown"
}
