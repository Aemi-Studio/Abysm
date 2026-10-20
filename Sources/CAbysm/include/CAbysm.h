#ifndef CABYSM_H
#define CABYSM_H

#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

/// The outcome of `abysm_invoke`.
typedef NS_CLOSED_ENUM(int, AbysmStatus) {
    AbysmStatusOK = 0,
    /// The target does not implement the selector (no method signature).
    AbysmStatusNoSignature = 1,
    /// The number of arguments differs from the selector's.
    AbysmStatusArgumentCount = 2,
    /// An argument or the result is a different size from the one the runtime expects.
    AbysmStatusSizeMismatch = 3,
    /// The call raised an Objective-C exception; its name is in `exceptionName`.
    AbysmStatusRaised = 4,
};

/// Sends `selector` to `target` — an instance, or a class object for a class method.
///
/// Arguments and the result travel by address, so any C type works. Every size is checked against the runtime's
/// own method signature before the call, so a wrong declaration cannot overrun a buffer. An exception raised by
/// the callee is caught and reported rather than unwinding through Swift, which cannot catch it.
///
/// @param args       `argc` pointers, one per explicit argument (receiver and selector are implicit).
/// @param argSizes   `argc` byte sizes, one per argument.
/// @param result     Where the return value is written; may be NULL when `resultSize` is 0.
/// @param resultSize Byte size of the return type; 0 for `void`.
AbysmStatus abysm_invoke(id target, SEL selector, size_t argc, const void *_Nullable const *_Nullable args,
                         const size_t *_Nullable argSizes, void *_Nullable result, size_t resultSize,
                         NSString *_Nullable *_Nullable exceptionName);

/// The method's signature as the runtime has it, receiver and selector included and offsets removed: the return
/// type followed by one type per argument, joined without separators (for example `@@:q` for `-(id)x:(NSInteger)`).
/// NULL when the class does not implement the selector.
NSString *_Nullable abysm_signature(Class cls, SEL selector, BOOL classMethod);

/// `-valueForKey:` with an exception caught. Returns nil with `exceptionName` set when it raised.
id _Nullable abysm_value_for_key(id target, NSString *key, NSString *_Nullable *_Nullable exceptionName);

/// `-setValue:forKey:` with an exception caught. Returns the exception name, or nil on success.
NSString *_Nullable abysm_set_value_for_key(id target, id _Nullable value, NSString *key);

NS_ASSUME_NONNULL_END

#endif
