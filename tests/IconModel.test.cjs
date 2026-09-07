'use strict';
const assert=require('node:assert/strict');
const Icons=require('../plugin/IconModel.js');
const entries=[
  {id:'Test Chat',icon:'chat-icon',execString:'omarchy-launch-webapp "https://chat.example.test/channels/@me"'},
  {id:'Test Maps',icon:'maps-icon',execString:'/usr/bin/omarchy-launch-webapp https://maps.example.test'},
  {id:'Native',icon:'native-icon',startupClass:'CustomNative',execString:'native'},
  {id:'Chromium App',icon:'browser-app-icon',command:['chromium','--app=https://app.example.test:8443/path/?q=one#part']},
  {id:'LowerPath',icon:'short-path',execString:'omarchy-launch-webapp https://example.test/foo'},
  {id:'LongerPath',icon:'long-path',execString:'omarchy-launch-webapp https://example.test/foo-bar'},
  {id:'No URL',icon:'wrong',execString:'echo https://unrelated.example.test'}
];
const index=Icons.buildIndex(entries);
assert.equal(Icons.iconName(index,'chrome-chat.example.test__channels_@me-Default'),'chat-icon');
assert.equal(Icons.iconName(index,'chrome-chat.example.test__channels_@me-Profile_2'),'chat-icon');
assert.equal(Icons.iconName(index,'chrome-maps.example.test__-Default'),'maps-icon');
assert.equal(Icons.iconName(index,'chrome-app.example.test__path_-Default'),'browser-app-icon');
assert.equal(Icons.iconName(index,'chrome-example.test__foo-bar-Default'),'long-path');
assert.equal(Icons.iconName(index,'CustomNative'),'native-icon');
assert.equal(Icons.iconName(index,'native'),'native-icon');
assert.equal(Icons.iconName(index,'chrome-unrelated.example.test__-Default'),'');
assert.equal(Icons.iconName(index,'constructor'),'');
assert.equal(Icons.webappKey('file:///private/test'),'');
assert.equal(Icons.webappKey('https://example.test/path?different#fragment'),'example.test__path');
assert.equal(Icons.launchUrl({execString:'browser --app "https://a.test/one"'}),'https://a.test/one');
assert.deepEqual(Icons.tokens('env NAME=value /bin/omarchy-launch-webapp "https://a.test/path?q=two words"'),
  ['env','NAME=value','/bin/omarchy-launch-webapp','https://a.test/path?q=two words']);
const updated=Icons.buildIndex([{...entries[0],icon:'new-chat-icon'}]);
assert.equal(Icons.iconName(updated,'chrome-chat.example.test__channels_@me-Default'),'new-chat-icon');
console.log('IconModel: desktop classes, URL applications, profiles and metadata replacement passed');
