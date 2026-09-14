# Changelog

## 0.1.0

- Add inspectable subscription/custom endpoint binding; only default options
  construction grants the fixed OpenCode Go subscription binding.
- Keep custom HTTPS roots explicit and non-forgeable, without public endpoint
  or credential accessors.
- Add the bounded authenticated OpenCode Go Chat Completions transport.
- Add package-owned cancellation, safe typed failures, and unauthenticated
  model catalog metadata.
- Add hermetic native transport tests, examples, and opt-in live verification.
