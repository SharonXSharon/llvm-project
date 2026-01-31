; RUN: opt -passes=hotcoldsplit -hotcoldsplit-threshold=0 -S < %s | FileCheck %s

target datalayout = "e-m:o-i64:64-f80:128-n8:16:32:64-S128"
target triple = "arm64-apple-ios14.0"

; Test that Swift once-wrapper functions (_WZ suffix) are not split.
; These functions implement thread-safe lazy initialization of static variables
; using atomic once-tokens. Splitting them can break the atomicity.

@once_token = internal global i64 0
@cached_value = internal global double 0.0

; Swift once-wrapper function - should NOT be split even though it has cold blocks
; CHECK-NOT: @"$s15QuickLayoutCore11ScreenScaleV5value_WZ{{.*}}.cold
; CHECK-LABEL: define {{.*}}@"$s15QuickLayoutCore11ScreenScaleV5value_WZ"(
; CHECK: call void @swift_once
; CHECK: ret double
define double @"$s15QuickLayoutCore11ScreenScaleV5value_WZ"() {
entry:
  %token = load atomic i64, ptr @once_token seq_cst, align 8
  %initialized = icmp eq i64 %token, -1
  br i1 %initialized, label %already_init, label %need_init

need_init:
  ; Cold path with unreachable - normally would be split
  call void @swift_once(ptr @once_token, ptr @init_screen_scale)
  call void @expensive_computation()
  call void @sink()
  unreachable

already_init:
  %cached = load double, ptr @cached_value, align 8
  ret double %cached
}

; Swift once-wrapper with LLVM suffix - should also NOT be split
; CHECK-NOT: @"$s24IGPremainStartupAnalyzerAAC6shared_WZ{{.*}}.cold
; CHECK-LABEL: define {{.*}}@"$s24IGPremainStartupAnalyzerAAC6shared_WZ.llvm.5439742213303041064"(
define ptr @"$s24IGPremainStartupAnalyzerAAC6shared_WZ.llvm.5439742213303041064"() {
entry:
  %token = load atomic i64, ptr @once_token seq_cst, align 8
  %initialized = icmp eq i64 %token, -1
  br i1 %initialized, label %already_init, label %need_init

need_init:
  call void @swift_once(ptr @once_token, ptr @init_screen_scale)
  call void @sink()
  unreachable

already_init:
  %cached = load ptr, ptr @cached_value, align 8
  ret ptr %cached
}

; Regular Swift function (not _WZ) - CAN be split
; CHECK-LABEL: define {{.*}}@"$s15QuickLayoutCore10otherFuncyyF"(
; CHECK: call {{.*}}@"$s15QuickLayoutCore10otherFuncyyF.cold
define void @"$s15QuickLayoutCore10otherFuncyyF"(i32 %cond) {
entry:
  %is_cold = icmp eq i32 %cond, 0
  br i1 %is_cold, label %cold_path, label %hot_path

cold_path:
  call void @expensive_computation()
  call void @another_expensive_call()
  call void @sink()
  unreachable

hot_path:
  ret void
}

; Test swift_once call in a non-_WZ function - block should not be extracted
; The function itself can be considered for splitting, but the block with
; swift_once should not be extracted
; CHECK-NOT: @test_swift_once_in_block{{.*}}.cold
; CHECK-LABEL: define {{.*}}@test_swift_once_in_block(
define void @test_swift_once_in_block(i32 %cond) {
entry:
  %is_cold = icmp eq i32 %cond, 0
  br i1 %is_cold, label %init_block, label %hot_path

init_block:
  ; This block calls swift_once and should not be extracted
  call void @swift_once(ptr @once_token, ptr @init_screen_scale)
  call void @sink()
  unreachable

hot_path:
  ret void
}

; Test dispatch_once - block should not be extracted
; CHECK-NOT: @test_dispatch_once{{.*}}.cold
; CHECK-LABEL: define {{.*}}@test_dispatch_once(
define void @test_dispatch_once(i32 %cond) {
entry:
  %is_cold = icmp eq i32 %cond, 0
  br i1 %is_cold, label %init_block, label %hot_path

init_block:
  call void @dispatch_once(ptr @once_token, ptr @init_screen_scale)
  call void @sink()
  unreachable

hot_path:
  ret void
}

declare void @swift_once(ptr, ptr)
declare void @dispatch_once(ptr, ptr)
declare void @init_screen_scale()
declare void @expensive_computation()
declare void @another_expensive_call()
declare void @sink() cold
