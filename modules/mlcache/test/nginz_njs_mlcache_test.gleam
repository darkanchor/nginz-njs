import gleeunit
import gleeunit/should
import metrics/line
import mlcache/lookup
import mlcache/metrics
import mlcache/model.{
  CacheConfig, Hit, Miss, RefreshOnMiss, RefreshStale, SharedDict, Stale,
  StaleTtlNegative, StaleWithNoWindow, TtlNotPositive,
}

pub fn main() {
  gleeunit.main()
}

// --- model: default_config ---

pub fn default_config_summary_test() {
  model.default_config()
  |> model.summary
  |> should.equal("shared_dict policy=refresh_on_miss ttl=60 stale=0")
}

pub fn default_config_fields_test() {
  let cfg = model.default_config()
  cfg.ttl_seconds |> should.equal(60)
  cfg.stale_ttl_seconds |> should.equal(0)
}

// --- model: summary ---

pub fn summary_refresh_stale_test() {
  CacheConfig(
    backend: SharedDict,
    refresh_policy: RefreshStale,
    ttl_seconds: 30,
    stale_ttl_seconds: 15,
  )
  |> model.summary
  |> should.equal("shared_dict policy=refresh_stale ttl=30 stale=15")
}

// --- model: validate ---

pub fn validate_valid_config_test() {
  model.default_config()
  |> model.validate
  |> should.be_ok
}

pub fn validate_valid_refresh_stale_test() {
  CacheConfig(
    backend: SharedDict,
    refresh_policy: RefreshStale,
    ttl_seconds: 60,
    stale_ttl_seconds: 30,
  )
  |> model.validate
  |> should.be_ok
}

pub fn validate_ttl_zero_test() {
  CacheConfig(
    backend: SharedDict,
    refresh_policy: RefreshOnMiss,
    ttl_seconds: 0,
    stale_ttl_seconds: 0,
  )
  |> model.validate
  |> should.equal(Error(TtlNotPositive))
}

pub fn validate_ttl_negative_test() {
  CacheConfig(
    backend: SharedDict,
    refresh_policy: RefreshOnMiss,
    ttl_seconds: -1,
    stale_ttl_seconds: 0,
  )
  |> model.validate
  |> should.equal(Error(TtlNotPositive))
}

pub fn validate_stale_ttl_negative_test() {
  CacheConfig(
    backend: SharedDict,
    refresh_policy: RefreshOnMiss,
    ttl_seconds: 60,
    stale_ttl_seconds: -1,
  )
  |> model.validate
  |> should.equal(Error(StaleTtlNegative))
}

pub fn validate_refresh_stale_no_window_test() {
  CacheConfig(
    backend: SharedDict,
    refresh_policy: RefreshStale,
    ttl_seconds: 60,
    stale_ttl_seconds: 0,
  )
  |> model.validate
  |> should.equal(Error(StaleWithNoWindow))
}

pub fn validate_ttl_checked_before_stale_test() {
  CacheConfig(
    backend: SharedDict,
    refresh_policy: RefreshOnMiss,
    ttl_seconds: 0,
    stale_ttl_seconds: -5,
  )
  |> model.validate
  |> should.equal(Error(TtlNotPositive))
}

// --- lookup: should_fetch ---

pub fn should_fetch_miss_test() {
  lookup.should_fetch(Miss)
  |> should.equal(True)
}

pub fn should_fetch_hit_test() {
  lookup.should_fetch(Hit("v"))
  |> should.equal(False)
}

pub fn should_fetch_stale_test() {
  lookup.should_fetch(Stale("v"))
  |> should.equal(False)
}

// --- lookup: should_refresh ---

pub fn should_refresh_miss_test() {
  lookup.should_refresh(Miss)
  |> should.equal(True)
}

pub fn should_refresh_stale_test() {
  lookup.should_refresh(Stale("v"))
  |> should.equal(True)
}

pub fn should_refresh_hit_test() {
  lookup.should_refresh(Hit("v"))
  |> should.equal(False)
}

// --- lookup: can_serve ---

pub fn can_serve_hit_any_policy_test() {
  lookup.can_serve(Hit("v"), RefreshOnMiss) |> should.equal(True)
  lookup.can_serve(Hit("v"), RefreshStale) |> should.equal(True)
}

pub fn can_serve_stale_refresh_stale_test() {
  lookup.can_serve(Stale("v"), RefreshStale)
  |> should.equal(True)
}

pub fn can_serve_stale_refresh_on_miss_test() {
  lookup.can_serve(Stale("v"), RefreshOnMiss)
  |> should.equal(False)
}

pub fn can_serve_miss_test() {
  lookup.can_serve(Miss, RefreshOnMiss) |> should.equal(False)
  lookup.can_serve(Miss, RefreshStale) |> should.equal(False)
}

// --- lookup: get_value ---

pub fn get_value_hit_test() {
  lookup.get_value(Hit("hello"))
  |> should.equal(Ok("hello"))
}

pub fn get_value_stale_test() {
  lookup.get_value(Stale("cached"))
  |> should.equal(Ok("cached"))
}

pub fn get_value_miss_test() {
  lookup.get_value(Miss)
  |> should.equal(Error(Nil))
}

// --- Metrics adapter ---

pub fn metrics_lookup_result_test() {
  line.render_statsd(metrics.lookup_result(Hit("cached")))
  |> should.equal("nginz.mlcache_lookup_total:1|c|#result:hit")
  line.render_statsd(metrics.lookup_result(Stale("cached")))
  |> should.equal("nginz.mlcache_lookup_total:1|c|#result:stale")
  line.render_statsd(metrics.lookup_result(Miss))
  |> should.equal("nginz.mlcache_lookup_total:1|c|#result:miss")
}

pub fn metrics_lock_attempt_test() {
  line.render_statsd(metrics.lock_attempt(True))
  |> should.equal("nginz.mlcache_lock_total:1|c|#result:acquired")
  line.render_statsd(metrics.lock_attempt(False))
  |> should.equal("nginz.mlcache_lock_total:1|c|#result:contended")
}
