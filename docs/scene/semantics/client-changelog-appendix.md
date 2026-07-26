# 官方客户端 changelog 全量附录（REV 3943-4401）

审查日期：2026-07-26
证据来源：`ui/dist/scripts/scripts.js`（SHA-256 `be104cf40bd7fe1e3598f7387f1cfa545c4a71282d9a3a3b30dcc4a8b262373e`，客户端 2.8.42）

> 本文是 [官方客户端 changelog 取证](client-changelog-forensics.md) 的全量数据附录：459 个 revision、741 条变更逐字固化。
> 分析、结论与使用边界见主文档；本文只按 REV 降序罗列原文，不做筛选或改写。
> 由 `script/extract_wallpaper_engine_client_evidence.py` 输出生成；官方客户端更新后重跑提取并整体重生成本文，不做手工增删。

## REV 4401

- Locale updates.

## REV 4400

- Added manual synchronization for NewDefaultAllocator because this is messed up in v8's design.

## REV 4399

- Enabled minidumps on breakpoint crashes from V8.

## REV 4398

- Updated bodymovin plugin.

## REV 4397

- Disabled application upload.

## REV 4396

- Disabled several chromium built-in features that are likely irrelevant for WE and just add bloat and issues.

## REV 4395

- Do not even allow UI to start when schema registration fails (why would that even fail, that's BS).

## REV 4394

- Added new architecture to handle invalid audio streams in scene player and better fall back to other configurations asynchronously.
- Changed internal URL schema for UI.
- Disabled media stream permissions on web wallpapers because, big surprise, some stupid thing in the new bloated chrome thing just causes this stupid thing to make a popup for 1 in 1000s users.
- Rebuilt CEF with fix to that sorting function where google violated their libcpp hardening and made it crash.

## REV 4393

- Completely removed audio stream from video texture when audio disabled through custom source descriptor.
- Added async video restart on delayed open failure due to bad codecs in video.
- Did full video framework restart on audio output flag change.

## REV 4392

- Added some more texture loading checks.

## REV 4391

- Fixing some texture loading issues.

## REV 4390

- SSE4.2 inclusive optimizations.

## REV 4389

- Fixed double url encoding on preview images.

## REV 4388

- Close video texture update thread when paused.

## REV 4387

- Added scene video present delay until first non fully black frame was received.

## REV 4386

- Added file hash checks for new CEF files that were still missing.

## REV 4385

- Changed back to basic synchronization because the other is too experimental.

## REV 4384

- Testing performing manual vsync at end of video work with dwmflush.

## REV 4383

- Added undocumented nvidia app flags to disable some injection BS that messes with WE.

## REV 4382

- Fixed crash in particle control point parse.

## REV 4381

- Added external frame sync to mfengine.

## REV 4380

- Prototyping workarounds for more of the absolute dogshit behaviors of the media foundation API.

## REV 4379

- Fixed incorrect size label.

## REV 4378

- Removed oversized handler cause it's not really usable after the fact.

## REV 4377

- Changed video size check to show warning but allow creation.

## REV 4376

- Changed video engine in editor to dx9 by default until we added missing editor functions like skipping.

## REV 4375

- Enabling stub handler in cef subprocesses again.

## REV 4374

- Optimizing some CEF launch flags.

## REV 4373

- Disabled custom exception handler from CEF subprocesses and enabled crash pad again.

## REV 4372

- Updated build script for more bitness changes.

## REV 4371

- Fixed modal confirm warning icon scaling behind text because chromium changed CSS behavior.

## REV 4370

- Also moving steamredownloadfixer to 64 bit because bitdefender is such a pos.

## REV 4369

- Changed service and installer to x64 too because BitDefender has worse behavior on x86 binaries.
- Disabled video texture looping on scene video wallpapers when playlist advance on end is expected.
- Fixed config version upgrade not setting old video player framework in correct location.

## REV 4368

- Fixed preview thumbnails of local files.

## REV 4367

- Made msdf font rasterization scaling dependent on global face size instead of character bbox.

## REV 4366

- Added drop shadow opacity.
- Added some properties default removal rules from scene config to reduce json bloat.

## REV 4365

- Updated buildscripts to match new .exe names.

## REV 4364

- Renamed modeldata update/replace to applyData/replaceData.

## REV 4363

- Updated translations.

## REV 4362

- Locale changes.

## REV 4361

- Added ability to create model data with shortcut without shapes array.

## REV 4360

- Fixed some model data update params not being handled as optional properly.

## REV 4359

- Version bump.

## REV 4358

- Optimized RB swap.

## REV 4357

- Added #undef support to custom preprocessor.

## REV 4356

- Fixed UI desync with shared materials on script run/stop.

## REV 4355

- Disallowed IModelData.replace in update().
- Fixed gl renderer not using depth write on alpha tested geometry.

## REV 4354

- Fixed android build dirs.

## REV 4353

- Fixed missing gl shader API for new model data feature.

## REV 4352

- Refactoring all model shaders with normal matrix uniform and removing redundant normal vector transforms.

## REV 4351

- Added msdfgen deps to android.

## REV 4350

- Renamed msdf font option.

## REV 4349

- Adjusted font fx limit values.

## REV 4348

- Fixed unused padding in msdf atlas.

## REV 4347

- Added font x/y spacing customization.

## REV 4346

- Split text padding into two axes.

## REV 4345

- Added font bezel test code.

## REV 4344

- Added msdfgen license.

## REV 4343

- Implemented all msdf font effects.

## REV 4342

- Added drop shadow to msdf fonts.

## REV 4341

- Added stubs for font drop shadow.
- Added font blur.

## REV 4340

- Added outline rendering support to msdf fonts.

## REV 4339

- Added character bbox cache to speed up text generation on known characters.

## REV 4338

- Optimizing font manager.

## REV 4337

- Added contour winding fix for user fonts in msdf.

## REV 4336

- Made one msdf texture shared across multiple font sizes and added on-demand color textures based on scaling multiplier.

## REV 4335

- Improved font color buffer quality by scaling color texture resolution with font size approximately.

## REV 4334

- Progress on supporting color fonts with msdf through bitmap conversion trick.

## REV 4333

- Added approximate bitmap to msdf conversion fallback for color fonts.

## REV 4332

- Made color fonts skip msdf path and render in second color pass again.

## REV 4331

- Progress on msdf fx support for text.

## REV 4330

- Split color and mono fonts in font manager.

## REV 4329

- Fixed normal mapping tangent space on modular shaders.

## REV 4328

- Updated some build tools to new x64 binary names.

## REV 4327

- Updated script language defs.

## REV 4326

- Fixed top level asset editing issues during project reload.

## REV 4325

- Fixed scripted layers not showing in asset browser.

## REV 4324

- Fixed url schema issue with preview image.

## REV 4323

- Added scripted layer asset tag for any type of layer that has scripts, so uploading only transform or camera layers etc is now possible.

## REV 4322

- Bonephysics fixes.

## REV 4321

- Update language def.

## REV 4320

- Removed now unused old Android API references.

## REV 4319

- Added msdfgen for advanced font rendering.

## REV 4318

- Updated scene script language def.
- Updated descriptions of video frameworks.
- Fixed generated/imported preview images missing local app redirection for new url scheme system.

## REV 4317

- Optimization for bone physics.
- Removed translation scaling from bone physics and adjusted UI to more fitting values.

## REV 4316

- Android compat.

## REV 4315

- Updated json libraries.

## REV 4314

- Fixed droplist in particle editor.
- More GLM custom perf optimizations.
- Optimized object render sorting with scratch memory and indirect handles.

## REV 4313

- Optimized matrix stack math.

## REV 4312

- Optimized some remaining GLM matrix operations in skeletal animation system that still ran poorly af.
- Added global aligned vector allocator utilities to facilitate SIMD instructions on basic glm::mat4.
- Improved V8 read vec/string binding speed.

## REV 4311

- Implemented custom scheme handler so the base UI can be loaded from a fake domain and garbage youtube embedder works again (insane x10).
- Since workshop cache is now invalid, added cache versioning and temporary version upgrade for browser.

## REV 4310

- Fixed custom textures on solid placeholders not importing correctly from workshop assets.

## REV 4309

- Reducing copies in property system bootstrap.
- Using transparent hash map where applicable.

## REV 4308

- Added support for numbers in min/max for all script Vec classes.
- Added generic transparent hash map definition.

## REV 4307

- Particle system optimization.

## REV 4306

- Fixed some compat issues with the UI as 64 bit.

## REV 4305

- Beginning particle system optimization.

## REV 4304

- More bone physics optimizations.

## REV 4303

- Fixed global materials props not updating on scene data update.

## REV 4302

- Made it possible to create a model layer directly from a model data object.

## REV 4301

- Cached some JS utility handles in createLayer.

## REV 4300

- Fixed bone physics glitchyness with inconsistent frame times.

## REV 4299

- Updated scene script language def.
- Improvements to bone physics world scaling.

## REV 4298

- Removing new bone physics test code again.

## REV 4297

- Fixed crash when editing models.

## REV 4296

- Fixed reflection map not working in chroma/veg/fur shaders.

## REV 4295

- New material gets auto selected.
- Added select/deselect all to clean modal.
- Fixed a bug in REMAP_VALUE_OPTION_SCALAR_POSITION_BETWEEN_TWO_CONTROL_POINTS.

## REV 4294

- Improved engine.userProperties stability when being modified to restore exact previous behavior.

## REV 4293

- Removed render target check on effectlayer causing texture map to fill up because this looks like a memory leak when spamming layers in a script.
- Inherited interpolation flag to user textures.

## REV 4292

- Added new basic math functions to language def.

## REV 4291

- Cleaning up scenescript language def.

## REV 4290

- Added user property cache against misuse of engine.userProperties.
- Updated language docs for modeldata.
- Added more JS baseline math utilities.
- Added precache system for registerAsset.
- Improved performance of final skeleton composition after SIMD animation.
- New container writer for across DLL boundary.

## REV 4289

- Added vertex input layout cache slot.

## REV 4288

- Added v8 script env to reduce string object overhead.

## REV 4287

- Adding vertexformat constants to IModelData.

## REV 4286

- Added script batch locking to many lifecycle hooks.
- Disabled multiline comment flatten in texture and combo parser because this also runs on cached files and needs to be as fast as possible.

## REV 4285

- Changed model data script interface to be part of modal data object.
- Added definition of scenescript component lifecycle hooks.
- Improvements to Json parsing speed.
- Moved model morphtexture into shared data.
- Removed manual double buffering for particles.
- Continued integration of modal data update/replace.

## REV 4284

- Further progress on improving shader precompiler.
- Optimized hlsl translator.

## REV 4283

- Added createModelData, updateModelData and destroyModelData script functions to create layers with custom geometry.
- Overhauled shader precompiler to run faster and handle certain complex directive setups more correctly.
- Added directories to asset window and ability to create custom materials (needed for dynamic models).
- Optimized V8 interface usage.
- Fixing some new CEF bugs due to all the useless chromium bloat being forced enabled in CEF for whatever insane reason.

## REV 4282

- Fixed meta data length.

## REV 4281

- Updated upload process.

## REV 4280

- Removed deprecated gradle settings and migrated to new.

## REV 4279

- Replaced devtools port with builtin devtools cause remote debugging is crap now.

## REV 4278

- Updating android build scripts.

## REV 4277

- Updating v8 on android.

## REV 4276

- Added v8 diff for windows.
- Updated code for new v8 version compatibility.

## REV 4275

- Upgraded android project.
- Improved ft/hb build scripts for android.

## REV 4274

- Finalized ft/hb update for win.

## REV 4273

- Finished ft and hb build system for win.

## REV 4272

- Started working on fully automated hb and ft update script.

## REV 4271

- Fixed build version script timestamp.
- Changed collection 2025 img.

## REV 4270

- Adjusting build tools for new exe names and arch.

## REV 4269

- Updated sass to sass-embedded.
- Updated CEF.
- Made UI use 64 bit.
- Renamed UI executable to wallpaper_ui.exe

## REV 4268

- Added CEF patch diffs to fix flicker on start.

## REV 4267

- Ordered all patches and CEF gen scripts.

## REV 4266

- Updated CEF build guides and scripts.

## REV 4265

- Updated web utility dependencies.

## REV 4264

- Updated android min sdk to 29 to be compatible with current V8 build for all target platforms.

## REV 4263

- Updated webview sdk and added more bullshit changes because the youtube api stopped working again immediately.

## REV 4262

- Added referrer policy to edge web wallpaper.
- Added more options for puppet warp animation baked smoothing.
- Defaulted video wallpaper to new backend for testing purposes on beta build.

## REV 4261

- Removing android boost lib.

## REV 4260

- Replaced filesystem library on Android with STL.
- Updated V8 to 14.0.
- Made video recreate window with different parameters when video backend changes.

## REV 4259

- Fixed fur shader occlusion factor.
- Fixed media engine deadlock during device loss.

## REV 4258

- Changed dx11 video backend to keep render thread alive and process device loss logic inside render thread by entirely reloading the scene.

## REV 4257

- Added preparations to handle device loss in dx11 video backend.

## REV 4256

- Improved new dx11 video backend when changing videos.
- Fixed reduce flicker transition (due to changed behavior in Windows?).
- Enabled shader framebuffer multiplication in particles again when refraction feature was used to reduce particle opacity instead of distortion.

## REV 4255

- Added all known video extensions to user video texture loader.

## REV 4254

- Added prototype for new dx11 video backend based on scene video texture system.
- Added flip and lut wallpaper properties to video wallpapers.
- Changed video textures to use keyed mutex.
- Changed video textures to use their own dedicated device and a shared texture for sync.
- Updated video textures from scene thread instead of using a separate thread.
- Fixed async texture loader not being able to handle 3D textures properly.
- Added generic property passthrough to video wallpaper because scene implementation needs raw property data (to be refactored).

## REV 4253

- Fixing yet another garbage android bug because Google changes how things work 24/7 for no reason.

## REV 4252

- Android kotlin garbage brokenness.
- Fixed cloudmotion effect on ogl.
- Hide particle normal map texture without lighting/refraction.
- Fixed particle collision not rendering in particle editor.

## REV 4251

- Stupid arbitrary google play native compile requirement.
- Fixed snackbar inset in preview activity due to stupid enforced edge to edge totally buggy UI framework behavior.
- Added clamp uvs option to texture import window.
- More work on voronoi texture helper.
- Fixed SIMD utils not initializing on android.
- Added new fire gradient.

## REV 4250

- Prevented wallpaper cache write if parse thread was interrupted.
- Disabled voronoi utilities in release mode.

## REV 4249

- Version bump.
- Added neutral lut.
- More voronoi generation utilities.
- Fixed user shortcut test button for the script callback.

## REV 4248

- Improved icon thumbnail rendering.
- Added experimental compiler puppet animations post smoothing.
- Added user property editor test buttons for user textures and user shortcuts.
- Improved editor click selection priority for complex measures where floating point imprecision leads to unexpected sorting.

## REV 4247

- Lock font-family for tree view box elements without icons in all languages.

## REV 4246

- Fixed editor model dialog crashing during model recompile.

## REV 4245

- Added new g_LayerModelMatrix constant to access unmodified model transform in effects.

## REV 4244

- Improved parallelism of steam subscription list query and subscription cache writing.

## REV 4243

- Another insane special function to **manually** parse the custom icon from a .url file because the Win API doesn't just FRIGGIN do it.
- Further fixes for hierarchy dragging with multiple collapsed items.

## REV 4242

- Locked media thumbnail generator to 256 cause with higher requests it will screw up potential fallback icons that it still outputs.
- Added default favicon path as a fallback to web shortcut loader.

## REV 4241

- Fixed uninitialized variable in thumbnail cache.

## REV 4240

- Added async loader support to dirty material refresh process.
- Reduced general settings callback to language only.
- Added **INSANE BS** to manually resolve .lnk files in 32-bit and do STUPID STRING operations to check for the 64-bit path which cannot be simply resolved by Windows in a clean way.
- Added **MORE INSANE BS** to load an icon from all image lists and do a pixel by pixel comparison to realize when Windows is using a SMALLER THAN REQUESTED icon but "scales" it up in a useless way by putting it into the top left of an EMPTY BITMAP. And not a single Windows API function returns the true size of an icon, not. a. single. one. of like a DOZEN different APIs that I ALL had to test.

## REV 4239

- Fixed scene hierarchy drag &amp; drop with collapsed elements in the list.
- Fixed workshop effect list not collapsing in gallery view.

## REV 4238

- Fixed handling of gif shortcut textures.
- Android studio update nonsense.

## REV 4237

- Fixed effect layer shared render target collisions with parents that use prerendering.

## REV 4236

- Fixed user shortcuts leading to video files being interpreted as user video textures.
- Added known folder support to shell icon thumbnails.

## REV 4235

- Forced default icon to folder if path is recognized as a directory but icon cannot be read.

## REV 4234

- Fixed web url not being adjusted on save.

## REV 4233

- Added search path to shell icon loader.
- Properly cleared invalid shortcut value so textures get reset.
- Added resize and cropping to web icons for bad touch icons that have arbitrary dimensions.

## REV 4232

- Fixed relative url icon loader not respecting redirect of original request.
- Made UI add url protocol automatically if missing so short urls will be accepted.

## REV 4231

- Moved thumbnail cache into separate file.
- Fixed click interactions being registered on top level list views.

## REV 4230

- Made user shortcut properties selectable for texture bindings.
- Added uri thumbnail loading to media system.
- Added custom thumbnail file cache for shell thumbnail texture loading.
- Changed ico loading from unknown to always load largest integrated bitmap.

## REV 4229

- Updated locales.

## REV 4228

- Fixed selection rect for world space particles.

## REV 4227

- Added doc button to particle editor.
- Removed blendmode option from blend effects when writing alpha.
- Fixed command args not being split properly from user shortcut.
- Added file member to user shortcut info in scenescript.

## REV 4226

- Changed write alpha function in blend effects to perform proper alpha and color transition.

## REV 4225

- Fixed HSV init random UI being black due to garbage web builder scripts.
- Added disable click propagation button to image, text and model layers.
- Implemented disable click propagation and 3D click sorting.
- Added default angles for control points.

## REV 4224

- Added token for disable interaction propagation.

## REV 4223

- Prevented deletion of custom effect source files in project clean dialog.

## REV 4222

- Fixed some translation issues.

## REV 4221

- Simpler description for sprite trail renderer.

## REV 4220

- Added generic hint to user shortcut modal.

## REV 4219

- Removed user shortcut properties from json sharing.
- Fixed hierarchy not closing in editor anymore.
- Fixed blend transform not being scaled with texture reduction.

## REV 4218

- Added unique system id to user shortcut config.
- Check variant names when filtering effect groups.
- Remember effect modal view in editor session.
- Fixed long user property labels breaking user property tab in editor.
- Added ability to set custom property order for shader parameters in editor.
- Added proper default values for size random initializer in 2D scenes.
- Fixed user shortcut script scope closing too early when hitting multiple layers.

## REV 4217

- Renamed system command modal.

## REV 4216

- Don't show preset publish options when there are only user shortcut properties.

## REV 4215

- Fixed user shortcut workshop tag support.

## REV 4214

- Renamed system command workshop tag to user shortcut

## REV 4213

- Renamed system command to user shortcut. engine.openUserShortcut for scripts and changed property type to usershortcut.

## REV 4212

- Removed dome template.
- Made sorting of Workshop assets alphabetical.
- Added sort by last date modified to open wallpaper modal in editor.

## REV 4211

- Fixed minimode/restore window behavior.
- Improved system command window layout in minimode.

## REV 4210

- Added fixed script system command types visible to creators.

## REV 4209

- Added test button for user system commands.

## REV 4208

- Added security warning to text inputs for system commands.

## REV 4207

- Added system command user property to open custom files/application/websites from a scene wallpaper.

## REV 4206

- Made asset layer publishing process consider child layer types of transform parent layers.
- Added hardware compression padding to texture sheets.

## REV 4205

- Fixed error texture for invalid external texture reference not being marked as missing anymore.

## REV 4204

- Fixed effect list modal not setting droplist index when changing items in gallery view to a workshop asset.

## REV 4203

- Fixed hierarchy transform code in client again.
- Improved general settings scene event.

## REV 4202

- Android development continues to be absolute garbage.

## REV 4201

- Added option to disable LUT back.

## REV 4200

- Added LUT materials.

## REV 4199

- Added LUT materials.

## REV 4198

- Added final LUTs.

## REV 4197

- Fixed lut options not being part of wallpaper defaults.

## REV 4196

- Fixed collision behavior not being applied through new template path for rotation controls.
- Disabled collision rotation behavior if there is no rotation used by the particle format.

## REV 4195

- Added applyGeneralSettings script callback to read a couple of general settings in scene wallpaper scripts.

## REV 4194

- Fixed layer pivot translate optimization.

## REV 4193

- Added gt, le, lt condition operators to passes etc.

## REV 4192

- Added complex condition support to shader passes, FBOs, bindings (only supporting ge operator for now).

## REV 4191

- Improved ember large preset and added ember beam preset.
- Added Belarusian as custom language.

## REV 4190

- New ember preview videos.

## REV 4189

- Fixed plane collision visualization when control point is world space but system isn't.

## REV 4188

- Fixed scene hierarchy vis toggles getting off sync with state on tree rebuild.
- Changed project and fullscreen layers on preset/workshop import to not apply shared camera center.

## REV 4187

- Adding preview videos back.

## REV 4186

- Trying to move preview videos to lfs.

## REV 4185

- Fixed new midas call structure.

## REV 4184

- Updated pymidas.

## REV 4183

- Added element preview videos.

## REV 4182

- Added video previews for all element add dialogs.
- Added basic static model particle collision based on geometry bounds.

## REV 4181

- Adding water preset previews.

## REV 4180

- Adding more particle element previews.

## REV 4179

- Disabled particle color override in hierarchy if root system doesn't apply override.
- Made particle cache and materials reload on preset import.

## REV 4178

- Only load puppet ref if file exists on global file system.

## REV 4177

- Added texture stubs to non-compiled texture loads.

## REV 4176

- Added stop rotation on collision flag.

## REV 4175

- Updated Android to API 35.
- Fixed event particle restarting emission on inherited property change.
- Reverted playlist duration preference to built-in duration time picker because Google has fixed the crash half a year ago, after it having being known for TWO YEARS.
- Fixed cpu downsampled read for RGB devices.
- Fixed crash when using video player script functions on non-video layer.
- Fixed planar reflection rendering.
- Made editor recognize video assets from precached asset list.
- Changed light limit errors to only be shown once during project open time.

## REV 4174

- Made new particle system code compatible with Android compilation.

## REV 4173

- Updated new stock particle sizes and added more variations.

## REV 4172

- Added rain screen stock particle.
- Added min length to sprite trail renderer.
- Added clamp output value to remap elements.
- Limited framebuffer updates to one per particle system.
- Added random seed to remap noise transforms.

## REV 4171

- Added more stock particle textures.
- Added new stock effects: vortex orb, color sparkle, rain splashes, water dripping/faucet/impact/droplets.
- Made it possible to duplicate particle elements in editor.
- Improved particle cutout shader option.
- Added particle movement operator option to apply gravity in worldspace.

## REV 4170

- Built additional stock particle textures.

## REV 4169

- Added lock distance to control point operator.

## REV 4168

- Added sound spatialization params.

## REV 4167

- Implemented sound spatialization.

## REV 4166

- Finished rope trail renderer alpha/size fade.

## REV 4165

- Refactored particle sprite VBO update.

## REV 4164

- Began adding rope trail alpha and size fading for scrolling UVs.
- Began working on sound spatialization.

## REV 4163

- Fixed vortex maintain distance with infinite axis.

## REV 4162

- Improved sphere emitter cone control.

## REV 4161

- Changed color correction to happen after basic color settings.

## REV 4160

- Fixed vortex operator infinite axis buffer setup.

## REV 4159

- Made luts compress to PNG to save space.

## REV 4158

- Added color correction user option to scenes.

## REV 4157

- Added 3d texture support to dxgi renderer.
- Made texture browser fullscreen.
- Added lut color correction to user post process image settings.
- Made gizmo plane rotate with gizmo when x/y angles are unchanged.

## REV 4156

- Updated fontawesome to 6.7.2.

## REV 4155

- Added option to hide control point gizmo in editor.
- Added stubs to make depth buffer readable in shaders.
- Changed 2D multi gizmo to lock XY plane tool on world axes.

## REV 4154

- Added rotation support to control points.
- Made emitters, vortex and map sequence around control point dependent on control point angles if applicable.
- Made collision plane and quad dependent on cp angles.
- Added inherit value from event initializer and operator.

## REV 4153

- Fixed child edit button in particle editor not connecting properly to new renderable.
- Added prototype for inherit event value initializer/operator.
- Changed boids speed cap to allow higher velocity if it was previously above cap.

## REV 4152

- Changed example 3D particles to use translucent but not additive blending.

## REV 4151

- Improved vortex operator with ring shape, pull and maintain distance.

## REV 4150

- Added cutout options to particle shaders.

## REV 4149

- Added refraction support to rope renderer.

## REV 4148

- Fixed tangent space of sprite trail renderer.
- Added uv scrolling option and uv multiplier to rope renderer.
- Sorted shader combo options for UI with dependencies in mind.
- Removed unmodified control points from particle config.
- Fixed particle emission stopping when rate becomes 0 due to instance multiplier.
- Made particle editor show correct material options when only a rope renderer is active.

## REV 4147

- Fixed caustics effect on android.

## REV 4146

- Changed swap chain mode to flip sequential.

## REV 4145

- Added normal mapping support to particle rope.

## REV 4144

- Added particle instance control for color list initializer.
- Added normal map for one smoke stock texture.

## REV 4143

- Added color list initializer.

## REV 4142

- Changed scene init DXGI factory to a more modern version.
- Sort particle names in particle editor properly.
- Added edit button to particle children.
- Right align particle child entries to discern them better.
- Made control points of presets import relative to layer origin.
- Fixed z shadow projection switch for reverse depth in cascaded shadow maps.
- Made gizmos render with multisampling.
- Made periodic emission limit scale with particle instance count.
- Added a flag to scale map initializers to scale with particle instance count.

## REV 4141

- Added glow to thunderbolt.
- More fixes for child particle transforms.

## REV 4140

- Added lighting support for particles.
- Added two new basic particle normal maps for lighting.
- Fixed getWallpaper command line not processing monitor/location.

## REV 4139

- Added remap operator blending support.

## REV 4138

- Added min/max to remap vector component selection.

## REV 4137

- Finished remap operator.

## REV 4136

- Moving SSE utilities into separate library.
- Replacing SSE constants with aligned arrays.

## REV 4135

- Began implementing remap operator.
- New 2D simplex SSE noise generator.
- Added remap transform functions.
- Added global variables to remap elements.

## REV 4134

- Reverting Windows sdk to 22621 for testing.

## REV 4133

- Finished remap initial value element.

## REV 4132

- Progress on remap initial value.

## REV 4131

- Added new thunderbolt preset.
- Continued work on remap initial value element.

## REV 4130

- Progress on particle attribute remap initializer.
- Updated JSONcpp  to 1.9.6.

## REV 4129

- Stubs for remap initial value element.

## REV 4128

- Changed command buffer structure and relaxed alignment requirement for buffers without vector instructions.

## REV 4127

- Added more options to disable various instance overrides for child particles.
- Improved/fixed more child particle transform issues.
- Added option to inherit control point from parent system

## REV 4126

- Added fbm position offset initializer.
- Made it possible to control clamp uvs and no interp for render targets when bound to a different material.

## REV 4125

- Added maintain distance between two control points and reduce movement near control point operators.
- Made periodic emission reset instant particles.
- Added option to limit periodic emission count for each period when rate emission is used.
- Disabled uv smoothing on rope particles that emit more particles than expected each frame.
- Changed map sequence initializers to match their number with instant emission count.

## REV 4124

- Made rope uv scroll assume that emitter rate is limited to FPS when deciding if max length is reached.

## REV 4123

- Improvements to dynamic rope uv offset.

## REV 4122

- Fixed some specific child transform cases.

## REV 4121

- Fixed child materials not reloading in main editor.

## REV 4120

- Fixed particle static child init not taking parent object transform into account.
- Added automatic uv offset to rope particle when its possible to predict a total, constant rope length for smoother rope rendering.

## REV 4119

- Added child particle precaching.

## REV 4118

- Fixed particle editor reload memory leak.

## REV 4117

- Disabled particle brightness inheritance when color modification is off.
- Updated some particle preview scenes.
- Fixed 3D cursor scene script position.
- Improved particle child transforms.
- Made color modification re-evaluate for each child particle.

## REV 4116

- Reduced default model collision bounce.

## REV 4115

- Made HSV color initializer dependent on instance color.

## REV 4114

- Changed instance update to be applied to all allocated children and not dormant particles on revival.
- Fixed emitter duration not decaying when max particle count is hit.

## REV 4113

- Fixes for instance particle color and brightness.

## REV 4112

- Progress on particle refactor.

## REV 4111

- Progress on particle refactor.

## REV 4110

- Progress on particle refactor.

## REV 4109

- Progress on particle refactor.

## REV 4108

- Fixed kinematics rope simulation not applying constraints in correct space to maintain lengths.
- Fixed particle editor element IDs.

## REV 4107

- Progress on particle refactor.

## REV 4106

- More progress on particle system refactor.

## REV 4105

- More progress on particle system refactor.

## REV 4104

- More progress on particle system refactor.

## REV 4103

- Changed new child config structure.

## REV 4102

- Began refactoring particle system classes to reduce JSON parsing and make child particles more lightweight.

## REV 4101

- Fixed layer transformation optimization.
- Changed particle rope renderer to use indices instead of moving data in vertex buffer around.

## REV 4100

- Removed unused particle layer dependencies from UI and json.

## REV 4099

- New particle default values for 3D scenes.

## REV 4098

- Added simulation skipping to boids and capsule collision operators to improve performance.
- Added pivot camera to particle editor in 3D scenes.
- Added capsule debug rendering to puppets.

## REV 4097

- Moved some assertions into debug only.

## REV 4096

- Added model capsule collider.
- Fixed model hitbox transforms.
- Fixed model match loop angle precision due to faulty quaternion conversion in GLM.
- Added cap velocity operator.
- Added operator blending to angular movement, oscillate pos, oscillate size, control point attract, turbulence, vortex.

## REV 4095

- Fixed model hitbox transforms.

## REV 4094

- Updating SSE2NEON to 1.8.0.

## REV 4093

- Added particle format system to improve performance by skipping unneeded particle components.

## REV 4092

- Improved control point attract deletion to be a bit more resilient for fast particles.

## REV 4091

- Fixed active emitter count underflow.
- Caching finished child particles for re-emission instead of creating new instances.
- Use modern random generator everywhere to improve rng perf.
- Made some vec3 code compatible with SIMD alignment.

## REV 4090

- Updated GLM to 10.1.

## REV 4089

- Removed some json copies from child particle instantiation.
- Improved performance of renderable buildtransform.
- Skip inactive control points in update functions.

## REV 4088

- Added inherit control point velocity initializer.

## REV 4087

- Added hsv color random preview.

## REV 4086

- Fixed hdr brightness particle instance value sometimes not being applied on particle creation.
- Added random HSV color initializer.

## REV 4085

- Added offset and random velocity to layer image emitter.

## REV 4084

- Added inherit layer motion to image emitter.

## REV 4083

- Made image emitter work for child particles.
- Added memory and simulation time info to particle editor.
- Fixed model editor commands overlapping so certain actions would be missing a response in the UI.
- Merged data cache classes in engine context.
- Added shared mdldata system for 3D models to save memory.

## REV 4082

- Progress on image emitter.
- Added hitbox debug draw to puppets.
- Changed UI checkbox visibility dependencies to allow for more complex setups.
- Made model bind pose available for image emitter.

## REV 4081

- Progress on image emitter.

## REV 4080

- Added emission mask to layer image emitter.

## REV 4079

- Progress on effect layer particle emitter.
- Allow nameless FBO creation without insertion in map.

## REV 4078

- Added undo for particle system file change on layer.
- Moved particle system file select button to top next to drop down UI.

## REV 4077

- Changed sphere emitter coords to allow cone angle adjustment along x axis.
- Added lock to control point bindings to most particle collision operators.

## REV 4076

- Added control point visualization option.

## REV 4075

- Fixed collision quad preview.

## REV 4074

- Updated particle collision sphere vis.

## REV 4073

- Fixed geometry shader rope particle triangle winding.
- Added particle collider and control point debug view options.
- Added particle collider rendering.
- Moved editor specific graphics flags into its own variable.

## REV 4072

- Made it possible to customize labels of 2D vector input property.

## REV 4071

- Implemented collision quad operator.

## REV 4070

- Added bounds collision operator.

## REV 4069

- Added particle sphere collision operator.
- Added additional collision operator stubs.
- Enabled reverse Z depth buffer on desktop.

## REV 4068

- Implemented multiple collision behaviors.

## REV 4067

- Added basic plane collision operator for particles.

## REV 4066

- Added particle initial emission delay.
- Added particle emitter random periodic emission settings.
- Fixed particle emission duration only decreasing on emission frames.
- Added boids operator preview.

## REV 4065

- Implemented particle boids operator with SIMD instructions.

## REV 4064

- Particle boids operator prototype without SIMD support.

## REV 4063

- Added control point auto deletion option when particle close to CP.
- Added captions and tags to particle element selector.

## REV 4062

- Added realtime preview to particle child selection.

## REV 4061

- Added arc and dampening to map particle between control points operator.
- Improved discharge particle and added arc discharge.
- Added preview support to particle element selection.
- Fixed sprite renderer not working when sprite trail renderer has been added too.
- Fixed playlist transition not starting when loading playlist from command line.

## REV 4060

- Added steelseries capture service to diagnostics because it interferes with basic directx rendering.

## REV 4059

- Fixed permission prompt showing up multiple times on android.
- Upgraded node-sass.
- Fixed rope particle screen orientation per rope segment.
- Finished implementing reverse z depth buffer compiler toggle.
- Fixed sprite occlusion test primitive not being hidden.
- Fixed variant conditions with combos not triggering texture reload based on current value.
- Fixed clean project function deleting texture variants.
- Fixed on video ended playlist trigger not starting fade window sequence.

## REV 4058

- Removed beta warning from editor.

## REV 4057

- Fixed blend rules not saving.
- Fixed blend rules on generic kinematics bone chains.

## REV 4056

- Optimized clipping mask alpha borders.

## REV 4055

- Added switch for experimental reverse z full float depth buffer for DXGI to fix z fighting on large 3D scenes.

## REV 4054

- Fixed clipping mask range index collection.
- Fixed clipping mask self overlay inside single mask pass.

## REV 4053

- Updated some bone constraint related translation tokens.

## REV 4052

- Added stubs for additional depth formats.

## REV 4051

- Changed rope physics slider min/max values.

## REV 4050

- Added best of 2025 query.

## REV 4049

- Fixed wind acceleration scaling.

## REV 4048

- Fixed preset publish.
- Removed vdesktop support on Windows 11 because it breaks with every Windows update due to lack of official support by Microsoft.
- Fixed a buffer overflow.

## REV 4047

- Reverted particle system child preload attempt again.

## REV 4046

- FFS.

## REV 4045

- Fixed texture variant not triggering reload when used with combos.

## REV 4044

- Fixed long platform tags not being replaced by script.

## REV 4043

- Updated texture optimization publish URL.

## REV 4042

- Updated water flow again.

## REV 4041

- Updated water flow effect.

## REV 4040

- Fixed move to position for parent elements.
- Cloud motion min values.
- Potentially fixed flipped rendering of complex composition setups.

## REV 4039

- Version bump.

## REV 4038

- Locales.

## REV 4037

- Added clipping mask pass count to stats.

## REV 4036

- Reverted Android SDK to version 34 because 35 is a super huge pain and we wasted enough time on that.
- Added nested clipping mask rendering support for OGL.

## REV 4035

- Added edge to edge opt-out for insane android garbage.

## REV 4034

- Fixed bone physics last world transform being invalid on first frame after refactor.

## REV 4033

- Fixed editor script labels.

## REV 4032

- Android updates.

## REV 4031

- Fixed DNA wallpaper not rendering on OGL.

## REV 4030

- Made rope simulation set initial simulation positions after first animation frame.

## REV 4029

- Added a snippet to generate new bokeh kernels.

## REV 4028

- Improved nested clipping mask rendering order.
- Changed clipping mask error to only display with nested configurations that don't resolve to a single clipping mask.

## REV 4027

- Added support for nested clipping masks.

## REV 4026

- Added a2c rendering to mask prerender.

## REV 4025

- Sorted texture compression hints by file size.

## REV 4024

- Added warning dialog when deleting user property.

## REV 4023

- Fixed wind 2d/depth vector construction.

## REV 4022

- Finished IK rope simulation.

## REV 4021

- Added error message when importing invalid variant texture.
- Progress on IK rope sim.
- Added global scene gravity and wind settings.
- Fixed anim buffer not resizing properly after scene change.

## REV 4020

- Added rope IK simulation implementation.
- Fixed light cookie texture being deleted while in use when media integration triggers a texture flush.

## REV 4019

- Fixed glitter aspect ratio scaling.
- Fixed cloud motion angle.

## REV 4018

- Made it possible to rename texture variant groups.

## REV 4017

- Changed texture variants using their original compression to allow transparency even when base image is stored as jpeg etc.
- Added origin only blend rule support.
- Improved some effect value ranges.
- Fixed memory leak in new undo system.

## REV 4016

- Experimental additional IK settings.

## REV 4015

- Updated shimmer and caustics effects.

## REV 4014

- Improved water caustics effect.

## REV 4013

- Added water caustics effect.

## REV 4012

- Added new shimmer and cloud motion effects.

## REV 4011

- Added puppet reference overlay offset position.

## REV 4010

- Added vertex edit gizmos to puppet geometry edit modes.
- Added blend shape bone point and axis modulation.
- Added local storage re-write on shutdown if any blocks got changed while writing was still occurring.
- Changed animation state buffer to only reallocate if required animation state data is larger than available buffer.

## REV 4009

- Changed IK axis locking when chain doesn't use axis alignment.

## REV 4008

- Added material src exclude.

## REV 4007

- Added UI for additional vertex editing tools.

## REV 4006

- Progress on additional IK blend rules.

## REV 4005

- Progress on additional IK blend rules.

## REV 4004

- Implemented support for multiple blend targets within a single expression.
- Fixed particle child prerender coordinate system for world particles.

## REV 4003

- Updated china apk disclaimers based on current requests.

## REV 4002

- Made inverted masked puppet geometry draw in depth-order without pulling it down to the mask.

## REV 4001

- Added vram and genre hints to upload dialog.

## REV 4000

- Locale fix.

## REV 3999

- Added spinlock back to fade window because windows must be doing some side effect in peekmessage.

## REV 3998

- Removed hack for transition window fixes to check whether the other fix solved all problems.
- Changed light limit behavior to allow adding more lights and choosing light count and features based on distance.
- Fixed layer move to bottom behavior with parent layers.

## REV 3997

- Added button to remove clipping mask from a limb.
- Added analysis for incorrect clipping mask setups and an alert box.

## REV 3996

- Fixed certain HSV blend modes in HDR.
- Added render target layer name to texture input.

## REV 3995

- Disabled some material settings when they are incompatible with the other current options.
- Fixed glitter on ogl.
- Added sub index buffers to ogl.
- Added new blend modes to ogl.

## REV 3994

- Disabled variant blend mode dropdown if format is unsupported.

## REV 3993

- Potential fixes for strange explorer interaction during fade window synchronization.

## REV 3992

- Fixed puppet index range depth priority calculation during animation.
- Added video texture support to texture variant system.
- Added texture replace function to texture variant UI.
- Fixed bone depth controls in UI lists that put IDs into key names.
- Added texture size on disk to texture info list.
- Fixed auto recompile not triggering for video textures due to missing extension recognition.

## REV 3991

- Fixed new wheel/key events being processed by inactive elements.

## REV 3990

- Progress on texture variant blending.

## REV 3989

- Fixed ref pose bone depth edit.
- Changed curve animation editor to also set keys for invisible objects changed from gizmos/controls (not the curve editor itself).
- Fixed scene script storage to use absolute path for hash from virtual file system instead of local path.

## REV 3988

- Progress on texture variant implementation.

## REV 3987

- Continued work on texture variants.
- Doubled z render range for orthogonal projection to fix old wallpapers that were relying on incorrect eye z pos on older builds.

## REV 3986

- Fixed default obj bone animation state when bones are scaled.
- Added 64 bit compiler.
- Began working on texture variants.
- Fixed sprite trail fps length adjustment.
- Fixed eye dropper picker window having an invisible border when it shouldn't.

## REV 3985

- Added JSON cache to improve child particle system instantiation time.

## REV 3984

- Added some clipping mask rendering options.
- Removed light limit and changed light system to render the closest lights only if light limit is reached.

## REV 3983

- Added localization for blend modes.

## REV 3982

- added glitter effect.
- Added masked default shader snippet to shader editor.
- Added sampler generator to shader editor.
- Added new perlin and uniform default textures.
- Added diffuse light blend mode to shader blend modes.

## REV 3981

- Updated LZ4.

## REV 3980

- Fixed crash from morph texture passthrough for clipping mask render path.
- Added depth factor to auto depth deformation generation.

## REV 3979

- Fixed topology editor and vertex cursor dragging when layer scale is non-uniform.

## REV 3978

- Fixed a puppet model compiler crash.

## REV 3977

- Added some verbose debug messages for testing purposes.

## REV 3976

- Added different clipping mask compose system for testing purposes.

## REV 3975

- Fixing some clipping mask render issues and material crash.

## REV 3974

- Added puppet depth auto generation using SDF.

## REV 3973

- Improved clipping mask range sorting.
- Fixed clipping mask render not using skinning.

## REV 3972

- Fixed sprite trail length fps compensation.

## REV 3971

- Moved shader bone animation data into separate buffer to only require single upload for entire model/puppet per frame.

## REV 3970

- Added low FPS preview option to editor.

## REV 3969

- Added additive blending option to clipping mask compositor.

## REV 3968

- Clipping mask implementation.
- Changed acceleration/deceleration in particle operators to use dampened dt for more consistent behavior with low fps.
- Fixed particle drag becoming to large and inverting velocity under low fps.
- Fixed default wallpaper properties being possible to be manipulated by pre-declaring them as user properties.

## REV 3967

- Fixed puppet compiler crash when model is missing initial weight initialization.
- Fixed puppet texture blending texture scale correction for non-lighting pre-render case.
- Began working on puppet clipping mask support.
- Added fix to avoid applying particle user color override to initial color when any operators/initializers would already multiply the color. Only enabled for new wallpapers.
- Changed general puppet warp undo/redo system to use json object copies instead of serialization.

## REV 3966

- Updated Steamworks.
- Added puppet island visibility toggles to weight editor.
- Fixed paint message dead lock when importing multiple videos in editor.
- Replaced all empty paint messages with a full paint init/teardown because that seems to be the only safe thing.

## REV 3965

- Changed async loader to block low priority tasks until scene main loader has processed all layers.
- Changed mip map streamer to load third detail level first.

## REV 3964

- Disabled compose layer children alpha writing on compose layers with background copy.

## REV 3963

- Fixed precomposed children not rendering last effect pass with alpha writing enabled.

## REV 3962

- Hide parallax settings on child layers since the parent element controls parallax in this case.

## REV 3961

- Fixed compose layer condition to disable puppet support on them.

## REV 3960

- Fixed compose layer without effects not rendering transparently with copy background disabled and children pre-rendered.

## REV 3959

- Fixed particle instance config not being applied on particle reload in editor.

## REV 3958

- Fixed VHS effect mask.
- Added custom key/wheel handler for number inputs because the stock behavior is terrible.

## REV 3957

- Fixed visible property in asset packs losing meta data when filtering.

## REV 3956

- Disabled color override on fireworks refract particle to fix background tinting.

## REV 3955

- Fixed degree conversion to work without rounding too.
- Enabled degree conversion rounding for generic properties and physics constraints.

## REV 3954

- Added missing user property main panel reload on inline binding change.

## REV 3953

- Progress on faster puppet anim editor undo.

## REV 3952

- Work on faster animation editor undo.

## REV 3951

- Save all puppet anims on animation edit (temporarily).

## REV 3950

- Fixed clone transitions being created in single wallpaper mode.

## REV 3949

- Changed clone cropping logic to hopefully cover all use cases now.

## REV 3948

- Updating pac man wallpaper for HDR and colorization support.
- Fixed some issues with particle color inheritance.
- Added ability to disable color overrides on child particles.
- Added missing interpolation filter initialization for layers without reference texture.

## REV 3947

- Fixed general transition random selection height.

## REV 3946

- Added general wallpaper select transition option.

## REV 3945

- Android locale.

## REV 3944

- Adding round option to degree binding converter and replaced dir brush model conversion.

## REV 3943

- Changed lockscreen crop to use 0, 0 reference monitor instead of user configured primary monitor.
- Prepared transition system to support running during manual wallpaper selection/preview.
