package middleware

import (
	"net/http"
)

// RequestBodySizeLimitMiddleware limits the size of incoming request bodies
// to prevent memory exhaustion DoS attacks
func RequestBodySizeLimitMiddleware(maxBytes int64) func(http.Handler) http.Handler {
	return func(next http.Handler) http.Handler {
		return http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
			// Only limit POST, PUT, PATCH requests
			if r.Method == "POST" || r.Method == "PUT" || r.Method == "PATCH" {
				// Use http.MaxBytesReader to limit request body size
				r.Body = http.MaxBytesReader(w, r.Body, maxBytes)
			}

			next.ServeHTTP(w, r)
		})
	}
}
