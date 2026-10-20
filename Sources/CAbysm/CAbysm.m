#import "CAbysm.h"
#import <objc/runtime.h>
#include <ctype.h>
#include <string.h>

// Objective-C method-family rules: ignore leading underscores; a lowercase continuation is not a family match.
// Custom ns_returns_retained/not_retained annotations are not in runtime encodings and are unsupported.
static BOOL abysm_family(SEL selector, const char *family) {
    const char *name = sel_getName(selector);
    while (*name == '_') name++;
    size_t length = strlen(family);
    return strncmp(name, family, length) == 0 && !islower((unsigned char)name[length]);
}

AbysmStatus abysm_invoke(id target, SEL selector, size_t argc, const void *const *args, const size_t *argSizes,
                         void *result, size_t resultSize, NSString **exceptionName) {
    @try {
    NSMethodSignature *signature = [target methodSignatureForSelector:selector];
    if (signature == nil) {
        return AbysmStatusNoSignature;
    }
    if (signature.numberOfArguments < 2 || signature.numberOfArguments - 2 != argc) {
        return AbysmStatusArgumentCount;
    }
    if (signature.methodReturnLength != resultSize) {
        return AbysmStatusSizeMismatch;
    }
    for (size_t index = 0; index < argc; index++) {
        NSUInteger size = 0;
        NSGetSizeAndAlignment([signature getArgumentTypeAtIndex:index + 2], &size, NULL);
        if (size != argSizes[index]) {
            return AbysmStatusSizeMismatch;
        }
    }

        NSInvocation *invocation = [NSInvocation invocationWithMethodSignature:signature];
        invocation.target = target;
        invocation.selector = selector;
        for (size_t index = 0; index < argc; index++) {
            [invocation setArgument:(void *)args[index] atIndex:(NSInteger)index + 2];
        }
        // init consumes one receiver reference, even when it returns a replacement. Lend it a separate +1
        // so the Swift caller's reference to the allocated receiver remains balanced.
        BOOL initialiser = abysm_family(selector, "init");
        if (initialiser) CFRetain((__bridge CFTypeRef)target);
        [invocation invoke];
        if (resultSize > 0 && result != NULL) {
            [invocation getReturnValue:result];
            if (strcmp(signature.methodReturnType, "@") == 0) {
                __unsafe_unretained id object = nil;
                memcpy(&object, result, sizeof(object));
                BOOL owned = initialiser || abysm_family(selector, "alloc") || abysm_family(selector, "new")
                    || abysm_family(selector, "copy") || abysm_family(selector, "mutableCopy");
                // Transfer one reference to Swift; it releases after decoding, also on a type mismatch.
                if (object != nil && !owned) CFRetain((__bridge CFTypeRef)object);
            }
        }
    } @catch (NSException *exception) {
        if (exceptionName != NULL) {
            *exceptionName = exception.name;
        }
        return AbysmStatusRaised;
    }
    return AbysmStatusOK;
}

NSString *abysm_signature(Class cls, SEL selector, BOOL classMethod) {
    Method method = classMethod ? class_getClassMethod(cls, selector) : class_getInstanceMethod(cls, selector);
    if (method == NULL) {
        return nil;
    }
    const char *encoding = method_getTypeEncoding(method);
    if (encoding == NULL) {
        return nil;
    }
    NSMethodSignature *signature = [NSMethodSignature signatureWithObjCTypes:encoding];
    if (signature == nil) {
        return nil;
    }
    NSMutableString *joined = [NSMutableString stringWithUTF8String:signature.methodReturnType];
    for (NSUInteger index = 0; index < signature.numberOfArguments; index++) {
        [joined appendFormat:@"%s", [signature getArgumentTypeAtIndex:index]];
    }
    return joined;
}

id abysm_value_for_key(id target, NSString *key, NSString **exceptionName) {
    @try {
        return [target valueForKey:key];
    } @catch (NSException *exception) {
        if (exceptionName != NULL) {
            *exceptionName = exception.name;
        }
        return nil;
    }
}

NSString *abysm_set_value_for_key(id target, id value, NSString *key) {
    @try {
        [target setValue:value forKey:key];
        return nil;
    } @catch (NSException *exception) {
        return exception.name;
    }
}
