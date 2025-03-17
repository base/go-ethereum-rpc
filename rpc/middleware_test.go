// Copyright 2023 The go-ethereum Authors
// This file is part of the go-ethereum library.
//
// The go-ethereum library is free software: you can redistribute it and/or modify
// it under the terms of the GNU Lesser General Public License as published by
// the Free Software Foundation, either version 3 of the License, or
// (at your option) any later version.
//
// The go-ethereum library is distributed in the hope that it will be useful,
// but WITHOUT ANY WARRANTY; without even the implied warranty of
// MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE. See the
// GNU Lesser General Public License for more details.
//
// You should have received a copy of the GNU Lesser General Public License
// along with the go-ethereum library. If not, see <http://www.gnu.org/licenses/>.

package rpc

import (
	"context"
	"reflect"
	"sync"
	"sync/atomic"
	"testing"
)

// TestService is a simple service for the middleware tests
type TestService struct{}

// Echo is a method that returns the input
func (s *TestService) Echo(ctx context.Context, val string) (string, error) {
	return val, nil
}

// Add is a method that adds two numbers
func (s *TestService) Add(ctx context.Context, a, b int) (int, error) {
	return a + b, nil
}

// middlewareTestConn is a mock implementation of jsonWriter for testing
type middlewareTestConn struct{}

func (mc *middlewareTestConn) writeJSON(ctx context.Context, v interface{}, isError bool) error {
	return nil
}
func (mc *middlewareTestConn) close() {}
func (mc *middlewareTestConn) closed() <-chan interface{} {
	ch := make(chan interface{})
	close(ch)
	return ch
}
func (mc *middlewareTestConn) remoteAddr() string { return "mock-conn" }
func (mc *middlewareTestConn) peerInfo() PeerInfo {
	return PeerInfo{Transport: "mock", RemoteAddr: "mock-conn"}
}

// TestMiddlewareExecution tests that middleware is executed correctly
func TestMiddlewareExecution(t *testing.T) {
	registry := &serviceRegistry{}

	var middlewareCalled int32
	registry.setMiddlewares([]Middleware{
		func(ctx context.Context, method string, args []reflect.Value, next func(ctx context.Context, method string, args []reflect.Value) *MethodResult) *MethodResult {
			atomic.AddInt32(&middlewareCalled, 1)
			return next(ctx, method, args)
		},
	})

	h := newHandler(context.Background(), &middlewareTestConn{}, randomIDGenerator(), registry, 0, 0)

	cb := &callback{
		fn:       reflect.ValueOf(func(ctx context.Context, s string) (string, error) { return s, nil }),
		rcvr:     reflect.Value{},
		argTypes: []reflect.Type{stringType},
		hasCtx:   true,
		errPos:   1,
	}

	msg := &jsonrpcMessage{Method: "test_echo"}
	args := []reflect.Value{reflect.ValueOf("hello")}
	h.runMethod(context.Background(), msg, cb, args)

	if atomic.LoadInt32(&middlewareCalled) != 1 {
		t.Errorf("Middleware was not called")
	}
}

// TestMiddlewareChain tests that multiple middlewares can be chained
func TestMiddlewareChain(t *testing.T) {
	registry := &serviceRegistry{}

	var order []int
	var mu sync.Mutex

	// Set up middlewares
	registry.setMiddlewares([]Middleware{
		// First middleware
		func(ctx context.Context, method string, args []reflect.Value, next func(ctx context.Context, method string, args []reflect.Value) *MethodResult) *MethodResult {
			mu.Lock()
			order = append(order, 1)
			mu.Unlock()

			result := next(ctx, method, args)

			mu.Lock()
			order = append(order, 4)
			mu.Unlock()

			return result
		},
		// Second middleware
		func(ctx context.Context, method string, args []reflect.Value, next func(ctx context.Context, method string, args []reflect.Value) *MethodResult) *MethodResult {
			mu.Lock()
			order = append(order, 2)
			mu.Unlock()

			result := next(ctx, method, args)

			mu.Lock()
			order = append(order, 3)
			mu.Unlock()

			return result
		},
	})

	h := newHandler(context.Background(), &middlewareTestConn{}, randomIDGenerator(), registry, 0, 0)

	intType := reflect.TypeOf(int(0))
	cb := &callback{
		fn:       reflect.ValueOf(func(ctx context.Context, a, b int) (int, error) { return a + b, nil }),
		rcvr:     reflect.Value{},
		argTypes: []reflect.Type{intType, intType},
		hasCtx:   true,
		errPos:   1,
	}

	msg := &jsonrpcMessage{Method: "test_add"}
	args := []reflect.Value{reflect.ValueOf(1), reflect.ValueOf(2)}
	h.runMethod(context.Background(), msg, cb, args)

	expected := []int{1, 2, 3, 4}
	mu.Lock()
	defer mu.Unlock()

	if len(order) != len(expected) {
		t.Errorf("Unexpected middleware execution count: got %d, want %d", len(order), len(expected))
	} else {
		for i, v := range order {
			if v != expected[i] {
				t.Errorf("Unexpected middleware execution order at position %d: got %d, want %d", i, v, expected[i])
			}
		}
	}
}

// TestServerMiddleware tests that middlewares can be set on the server
func TestServerMiddleware(t *testing.T) {
	server := NewServer()

	// Register the test service
	if err := server.RegisterName("test", new(TestService)); err != nil {
		t.Fatalf("Failed to register test service: %v", err)
	}

	var middlewareCalled int32

	// Set middleware on the server
	server.SetMiddlewares([]Middleware{
		func(ctx context.Context, method string, args []reflect.Value, next func(ctx context.Context, method string, args []reflect.Value) *MethodResult) *MethodResult {
			atomic.AddInt32(&middlewareCalled, 1)
			return next(ctx, method, args)
		},
	})

	// Create a handler that would use the server's registry
	h := newHandler(context.Background(), &middlewareTestConn{}, randomIDGenerator(), &server.services, 0, 0)

	// Create a callback for testing
	cb := &callback{
		fn:       reflect.ValueOf(func(ctx context.Context, s string) (string, error) { return s, nil }),
		rcvr:     reflect.Value{},
		argTypes: []reflect.Type{stringType},
		hasCtx:   true,
		errPos:   1,
	}

	// Call the method
	msg := &jsonrpcMessage{Method: "test_echo"}
	args := []reflect.Value{reflect.ValueOf("hello")}
	h.runMethod(context.Background(), msg, cb, args)

	// Verify middleware was called
	if atomic.LoadInt32(&middlewareCalled) != 1 {
		t.Errorf("Server middleware was not called")
	}
}
