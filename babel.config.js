module.exports = function(api) {
  var validEnv = ['development', 'test', 'production']
  var currentEnv = api.env()
  var isDevelopmentEnv = api.env('development')
  var isProductionEnv = api.env('production')
  var isTestEnv = api.env('test')

  if (!validEnv.includes(currentEnv)) {
    throw new Error(
      'Please specify a valid `NODE_ENV` or ' +
        '`BABEL_ENV` environment variables. Valid values are "development", ' +
        '"test", and "production". Instead, received: ' +
        JSON.stringify(currentEnv) +
        '.'
    )
  }

  return {
    // Babel 8 replaces the per-plugin `loose` and `useBuiltIns` options with top-level assumptions.
    assumptions: {
      setPublicClassFields: true,
      privateFieldsAsProperties: true,
      setSpreadProperties: true
    },
    presets: [
      isTestEnv && [
        '@babel/preset-env',
        {
          targets: {
            node: 'current'
          }
        }
      ],
      (isProductionEnv || isDevelopmentEnv) && [
        '@babel/preset-env',
        {
          forceAllTransforms: true,
          modules: false,
          exclude: ['transform-typeof-symbol']
        }
      ]
    ].filter(Boolean),
    plugins: [
      // preset-env 8 dropped useBuiltIns/corejs; core-js entry polyfills now come from this plugin.
      (isProductionEnv || isDevelopmentEnv) && [
        'babel-plugin-polyfill-corejs3',
        {
          method: 'entry-global',
          version: '3'
        }
      ],
      '@babel/plugin-transform-destructuring',
      // transform-runtime is gone: in Babel 8 it only injects helper imports, which this config never wanted,
      // and the regenerator runtime is now an inlined helper.
      '@babel/plugin-transform-regenerator'
    ].filter(Boolean)
  }
}
