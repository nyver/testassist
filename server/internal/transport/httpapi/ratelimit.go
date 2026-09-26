package httpapi

import (
	"context"
	"net"
	"net/http"
	"sync"
	"time"

	"golang.org/x/time/rate"

	"github.com/nyver/test-assistant/server/internal/apierr"
	"github.com/nyver/test-assistant/server/internal/config"
)

const (
	limiterIdleTTL       = 10 * time.Minute
	limiterSweepInterval = time.Minute
)

// ipLimiter keeps one token bucket per client IP. Entries of idle clients are
// evicted by a janitor so memory stays bounded.
type ipLimiter struct {
	limit rate.Limit
	burst int
	now   func() time.Time

	mu      sync.Mutex
	clients map[string]*clientLimiter
}

type clientLimiter struct {
	lim      *rate.Limiter
	lastSeen time.Time
}

func newIPLimiter(cfg config.RateConfig, now func() time.Time) *ipLimiter {
	return &ipLimiter{
		limit:   rate.Limit(cfg.RequestsPerMinute / 60),
		burst:   cfg.Burst,
		now:     now,
		clients: make(map[string]*clientLimiter),
	}
}

// allow takes one token for ip. When none is available it returns false and
// how long the client should wait.
func (l *ipLimiter) allow(ip string) (bool, time.Duration) {
	now := l.now()

	l.mu.Lock()
	defer l.mu.Unlock()
	c, ok := l.clients[ip]
	if !ok {
		c = &clientLimiter{lim: rate.NewLimiter(l.limit, l.burst)}
		l.clients[ip] = c
	}
	c.lastSeen = now

	res := c.lim.ReserveN(now, 1)
	if !res.OK() {
		return false, time.Minute
	}
	if delay := res.DelayFrom(now); delay > 0 {
		res.CancelAt(now) // a rejected request must not consume a token
		return false, delay
	}
	return true, 0
}

// evict removes clients that have been idle longer than limiterIdleTTL.
func (l *ipLimiter) evict() {
	cutoff := l.now().Add(-limiterIdleTTL)
	l.mu.Lock()
	defer l.mu.Unlock()
	for ip, c := range l.clients {
		if c.lastSeen.Before(cutoff) {
			delete(l.clients, ip)
		}
	}
}

func (l *ipLimiter) size() int {
	l.mu.Lock()
	defer l.mu.Unlock()
	return len(l.clients)
}

// run evicts idle clients periodically until ctx is done. The server owns the
// goroutine that calls it and waits for it on shutdown.
func (l *ipLimiter) run(ctx context.Context) {
	t := time.NewTicker(limiterSweepInterval)
	defer t.Stop()
	for {
		select {
		case <-ctx.Done():
			return
		case <-t.C:
			l.evict()
		}
	}
}

// middleware rejects requests over the limit with RATE_LIMITED.
func (l *ipLimiter) middleware(next http.Handler) http.Handler {
	return http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		if ok, wait := l.allow(clientIP(r)); !ok {
			e := apierr.New(apierr.RateLimited, "Too many requests.")
			e.RetryAfter = wait
			writeError(w, r, e)
			return
		}
		next.ServeHTTP(w, r)
	})
}

// clientIP is the peer address of the connection. There is no proxy trust in
// this version, so forwarding headers are deliberately ignored.
func clientIP(r *http.Request) string {
	host, _, err := net.SplitHostPort(r.RemoteAddr)
	if err != nil {
		return r.RemoteAddr
	}
	return host
}
