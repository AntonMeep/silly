const webpack = require('webpack')
const ExtractTextPlugin = require('extract-text-webpack-plugin')
const CopyWebpackPlugin = require('copy-webpack-plugin')
const path = require('path')

const extractSass = new ExtractTextPlugin({
	filename: "styles.css",
});

module.exports = {
	entry: './src/index.js',
	output: {
		filename: 'app.js',
		path: path.resolve(__dirname, 'public')
	},
	module: {
		rules: [
			{
				test: /\.js$/,
				include: path.resolve(__dirname, 'src'),
				use: [{
					loader: 'babel-loader',
					options: {
						presets: [
							['es2015', { modules: false }]
						]
					}
				}]
			},
			{
				test: /\.(scss)$/,
				use: extractSass.extract({
					fallback: 'style-loader',
					//resolve-url-loader may be chained before sass-loader if necessary
					use: [{
						loader: "css-loader" // translates CSS into CommonJS
					}, {
						loader: "sass-loader" // compiles Sass to CSS
					}]
				})
			}
		]
	},
	plugins: [
		new webpack.ProvidePlugin({
			$: "jquery", // Used for Bootstrap JavaScript components
			jQuery: "jquery", // Used for Bootstrap JavaScript components
			Popper: ['popper.js', 'default'] // Used for Bootstrap dropdown, popup and tooltip JavaScript components
		}),
		extractSass,
		new CopyWebpackPlugin([
			{
				from: './src/*.html',
				flatten: true
			},
			{
				from: './src/*.svg',
				flatten: true
			}
		])
	]
};