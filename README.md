# go-ethereum-rpc

A fork of the `rpc` package in https://github.com/ethereum/go-ethereum with extensions.

The go-ethereum JSON RPC server is one of the most mature Golang RPC server implementations, but lacks some features that would make it a better general-purpose JSON RPC server. 
This package is intended to be a minimal fork of ethereum/go-ethereum, such that it can easily be kept up to date with modifications to go-ethereum.

## RPC Middleware

This package adds middleware support to the go-ethereum JSON RPC server. Middleware allows you to intercept and modify RPC method calls before and after they are executed. This provides a central hook to enable functionality such as:

- Logging and metrics collection
- Request validation
- Authentication and authorization
- Error handling and transformation
- Caching
- Rate limiting

### Usage

#### Setting Middlewares on a Server

```go
// Create a new RPC server
server := rpc.NewServer()

// Set middlewares on the server
server.SetMiddlewares([]rpc.Middleware{
    // Logging middleware
    func(ctx context.Context, method string, args []reflect.Value, next func(ctx context.Context, method string, args []reflect.Value) rpc.MethodResult) rpc.MethodResult {
        log.Printf("Calling method %s", method)
        
        // Call the next middleware or the actual method
        result := next(ctx, method, args)
        
        log.Printf("Method %s completed", method)
        if result.Error != nil {
            log.Printf("Method %s failed with error: %v", method, result.Error)
        }
        
        return result
    },
    // Another middleware
    func(ctx context.Context, method string, args []reflect.Value, next func(ctx context.Context, method string, args []reflect.Value) rpc.MethodResult) rpc.MethodResult {
        // Do something before the method call
        
        result := next(ctx, method, args)
        
        // Do something after the method call
        
        return result
    },
})
```

#### Middleware Execution Order

Middlewares are executed in the order they are provided to `SetMiddlewares`. The "before" parts are executed in the order they were added, and the "after" parts are executed in reverse order.

For example, if you add middlewares A, B, and C in that order, the execution flow will be:

```
A (before) -> B (before) -> C (before) -> Method -> C (after) -> B (after) -> A (after)
```

#### Middleware Function Signature

```go
type Middleware func(ctx context.Context, method string, args []reflect.Value, next func(ctx context.Context, method string, args []reflect.Value) MethodResult) MethodResult
```

Where:
- `ctx` is the context for the method call
- `method` is the name of the method being called
- `args` are the arguments to the method
- `next` is the next middleware in the chain, or the actual method if this is the last middleware
- `MethodResult` is a struct containing the result and error from the method call

### Examples

#### Logging Middleware

```go
func LoggingMiddleware(ctx context.Context, method string, args []reflect.Value, next func(ctx context.Context, method string, args []reflect.Value) rpc.MethodResult) rpc.MethodResult {
    start := time.Now()
    log.Printf("Calling method %s", method)
    
    result := next(ctx, method, args)
    
    log.Printf("Method %s completed in %v", method, time.Since(start))
    if result.Error != nil {
        log.Printf("Method %s failed with error: %v", method, result.Error)
    }
    
    return result
}
```

### Best Practices

1. **Keep middlewares focused**: Each middleware should have a single responsibility.
2. **Consider performance**: Be mindful of performance implications, especially for high-traffic RPC servers.
3. **Use context for data sharing**: Use context values to pass data between middlewares.
4. **Handle errors appropriately**: Decide whether to pass errors through or transform them.
5. **Order matters**: Consider the order of middleware execution carefully.
