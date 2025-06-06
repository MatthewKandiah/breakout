package main

import "base:intrinsics"
import "base:runtime"
import "core:fmt"
import "core:math/linalg/glsl"
import "core:os"
import "core:time"
import "vendor:glfw"
import stbi "vendor:stb/image"
import vk "vendor:vulkan"

REQUIRED_LAYER_NAMES := []cstring{"VK_LAYER_KHRONOS_validation"}
REQUIRED_EXTENSION_NAMES := []cstring{vk.KHR_SWAPCHAIN_EXTENSION_NAME}
MAX_FRAMES_IN_FLIGHT :: 2
WINDOW_WIDTH_INITIAL :: 800
WINDOW_HEIGHT_INITIAL :: 600
VERTEX_BUFFER_LEN :: 1_000
INDEX_BUFFER_LEN :: 1_000
VERTEX_BUFFER_SIZE :: VERTEX_BUFFER_LEN * size_of(Vertex)
INDEX_BUFFER_SIZE :: INDEX_BUFFER_LEN * size_of(u32)

white :: glsl.vec3{1, 1, 1}
black :: glsl.vec3{0, 0, 0}
grey :: glsl.vec3{0.6, 0.6, 0.6}
pink :: glsl.vec3{1, 0, 1}
green :: glsl.vec3{0, 1, 0}
yellow :: glsl.vec3{1, 1, 0}
red :: glsl.vec3{1, 0, 0}
cyan :: glsl.vec3{0, 1, 1}

Vertex :: struct {
	pos:       glsl.vec2,
	col:       glsl.vec3,
	tex_coord: glsl.vec2,
}

vertex_input_binding_description := vk.VertexInputBindingDescription {
	binding   = 0,
	stride    = size_of(Vertex),
	inputRate = .VERTEX,
}

vertex_input_attribute_descriptions := []vk.VertexInputAttributeDescription {
	{binding = 0, location = 0, format = .R32G32_SFLOAT, offset = cast(u32)offset_of(Vertex, pos)},
	{
		binding = 0,
		location = 1,
		format = .R32G32B32_SFLOAT,
		offset = cast(u32)offset_of(Vertex, col),
	},
	{
		binding = 0,
		location = 2,
		format = .R32G32_SFLOAT,
		offset = cast(u32)offset_of(Vertex, tex_coord),
	},
}

RendererState :: struct {
	command_buffers:                 [MAX_FRAMES_IN_FLIGHT]vk.CommandBuffer,
	command_pool:                    vk.CommandPool,
	descriptor_pool:                 vk.DescriptorPool,
	descriptor_set_layout:           vk.DescriptorSetLayout,
	descriptor_sets:                 [MAX_FRAMES_IN_FLIGHT]vk.DescriptorSet,
	device:                          vk.Device,
	frame_buffer_resized:            bool,
	frame_index:                     u32,
	graphics_pipeline:               vk.Pipeline,
	graphics_queue:                  vk.Queue,
	graphics_queue_family_index:     u32,
	index_buffers:                   [MAX_FRAMES_IN_FLIGHT]vk.Buffer,
	index_buffers_mapped:            [MAX_FRAMES_IN_FLIGHT]rawptr,
	index_buffers_memory:            [MAX_FRAMES_IN_FLIGHT]vk.DeviceMemory,
	instance:                        vk.Instance,
	physical_device:                 vk.PhysicalDevice,
	pipeline_layout:                 vk.PipelineLayout,
	present_mode:                    vk.PresentModeKHR,
	present_queue:                   vk.Queue,
	present_queue_family_index:      u32,
	render_pass:                     vk.RenderPass,
	shader_module_fragment:          vk.ShaderModule,
	shader_module_vertex:            vk.ShaderModule,
	surface:                         vk.SurfaceKHR,
	surface_capabilities:            vk.SurfaceCapabilitiesKHR,
	swapchain:                       vk.SwapchainKHR,
	swapchain_extent:                vk.Extent2D,
	swapchain_format:                vk.SurfaceFormatKHR,
	swapchain_framebuffers:          []vk.Framebuffer,
	swapchain_image_index:           u32,
	swapchain_image_views:           []vk.ImageView,
	swapchain_images:                []vk.Image,
	sync_fences_in_flight:           [MAX_FRAMES_IN_FLIGHT]vk.Fence,
	sync_semaphores_image_available: [MAX_FRAMES_IN_FLIGHT]vk.Semaphore,
	sync_semaphores_render_finished: [MAX_FRAMES_IN_FLIGHT]vk.Semaphore,
	texture_image:                   vk.Image,
	texture_image_memory:            vk.DeviceMemory,
	texture_image_view:              vk.ImageView,
	texture_sampler:                 vk.Sampler,
	vertex_buffers:                  [MAX_FRAMES_IN_FLIGHT]vk.Buffer,
	vertex_buffers_mapped:           [MAX_FRAMES_IN_FLIGHT]rawptr,
	vertex_buffers_memory:           [MAX_FRAMES_IN_FLIGHT]vk.DeviceMemory,
	window:                          glfw.WindowHandle,
}

setup_renderer :: proc() -> RendererState {
	state: RendererState

	{ 	// set up window
		if !glfw.Init() {
			panic("glfwInit failed")
		}

		error_callback :: proc "c" (error: i32, description: cstring) {
			context = runtime.default_context()
			fmt.eprintln("ERROR", error, description)
			panic("glfw error")
		}
		glfw.SetErrorCallback(error_callback)

		// create window
		glfw.WindowHint(glfw.CLIENT_API, glfw.NO_API)
		glfw.WindowHint(glfw.RESIZABLE, glfw.TRUE)
		state.window = glfw.CreateWindow(
			WINDOW_WIDTH_INITIAL,
			WINDOW_HEIGHT_INITIAL,
			"bouncing ball",
			nil,
			nil,
		)
		if state.window == nil {panic("glfw create window failed")}

		// handle window resizes
		glfw.SetWindowUserPointer(state.window, &state)
		framebuffer_resize_callback :: proc "c" (
			window: glfw.WindowHandle,
			width: i32,
			height: i32,
		) {
			state := cast(^RendererState)glfw.GetWindowUserPointer(window)
			state.frame_buffer_resized = true
		}
		glfw.SetFramebufferSizeCallback(state.window, framebuffer_resize_callback)
	}

	{ 	// initialise Vulkan instance
		context.user_ptr = &state
		get_proc_address :: proc(p: rawptr, name: cstring) {
			state := cast(^RendererState)context.user_ptr
			(cast(^rawptr)p)^ = glfw.GetInstanceProcAddress(state.instance, name)
		}
		vk.load_proc_addresses(get_proc_address)
		application_info := vk.ApplicationInfo {
			sType              = .APPLICATION_INFO,
			pApplicationName   = "bouncing ball",
			applicationVersion = vk.MAKE_VERSION(1, 0, 0),
			pEngineName        = "magic",
			engineVersion      = vk.MAKE_VERSION(1, 0, 0),
			apiVersion         = vk.API_VERSION_1_0,
		}
		glfw_extensions := glfw.GetRequiredInstanceExtensions()
		if !check_validation_layer_support() {
			fmt.eprintln("validation layers not supported")
			panic("validation layers not supported")
		}
		instance_create_info := vk.InstanceCreateInfo {
			sType                   = .INSTANCE_CREATE_INFO,
			pApplicationInfo        = &application_info,
			enabledExtensionCount   = cast(u32)len(glfw_extensions),
			ppEnabledExtensionNames = raw_data(glfw_extensions),
			enabledLayerCount       = cast(u32)len(REQUIRED_LAYER_NAMES),
			ppEnabledLayerNames     = raw_data(REQUIRED_LAYER_NAMES),
		}
		if vk.CreateInstance(&instance_create_info, nil, &state.instance) != .SUCCESS {
			panic("create instance failed")
		}
	}

	{ 	// create vulkan window surface
		if glfw.CreateWindowSurface(state.instance, state.window, nil, &state.surface) !=
		   vk.Result.SUCCESS {
			panic("create window surface failed")
		}
	}

	{ 	// get physical device
		physical_devices := get_physical_devices(state.instance)
		for physical_device in physical_devices {
			properties: vk.PhysicalDeviceProperties
			if !check_extension_support(physical_device) {
				continue
			}
			if !check_feature_support(physical_device) {
				continue
			}
			vk.GetPhysicalDeviceProperties(physical_device, &properties)
			if properties.deviceType == .DISCRETE_GPU {
				state.physical_device = physical_device
				break
			} else if properties.deviceType == .INTEGRATED_GPU {
				state.physical_device = physical_device
			}
		}
		if state.physical_device == nil {
			panic("failed to get physical device")
		}
		delete(physical_devices)
	}

	{ 	// create logical device
		queue_family_properties := get_queue_family_properties(state.physical_device)
		graphics_index_found: bool = false
		present_index_found: bool = false
		for i: u32 = 0; i < cast(u32)len(queue_family_properties); i += 1 {
			queue_family_properties := queue_family_properties[i]
			if vk.QueueFlag.GRAPHICS in queue_family_properties.queueFlags {
				state.graphics_queue_family_index = i
				graphics_index_found = true
			}
			present_supported: b32
			if res := vk.GetPhysicalDeviceSurfaceSupportKHR(
				state.physical_device,
				i,
				state.surface,
				&present_supported,
			); res != vk.Result.SUCCESS {
				panic("failed to check surface presentation support")
			}
			if present_supported {
				state.present_queue_family_index = i
				present_index_found = true
			}
			// seems simplest to just use one queue family if possible? Not sure what's actually best to do here
			if present_index_found &&
			   graphics_index_found &&
			   state.graphics_queue_family_index == state.present_queue_family_index {
				break
			}
		}
		delete(queue_family_properties)
		if !graphics_index_found {
			panic("failed to find graphics queue family index")
		}
		if !present_index_found {
			panic("failed to find present queue family index")
		}
		if state.graphics_queue_family_index != state.present_queue_family_index {
			panic(
				"assumed from here that graphics and present queues are using the same queue family index",
			)
		}
		queue_priority: f32 = 1
		device_queue_create_info := vk.DeviceQueueCreateInfo {
			sType            = .DEVICE_QUEUE_CREATE_INFO,
			queueFamilyIndex = state.graphics_queue_family_index,
			queueCount       = 1,
			pQueuePriorities = &queue_priority,
		}
		queue_create_infos: []vk.DeviceQueueCreateInfo = {device_queue_create_info}
		required_device_features := vk.PhysicalDeviceFeatures {
			samplerAnisotropy = true,
		}
		device_create_info := vk.DeviceCreateInfo {
			sType                   = .DEVICE_CREATE_INFO,
			pQueueCreateInfos       = raw_data(queue_create_infos),
			queueCreateInfoCount    = cast(u32)len(queue_create_infos),
			ppEnabledExtensionNames = raw_data(REQUIRED_EXTENSION_NAMES),
			enabledExtensionCount   = cast(u32)len(REQUIRED_EXTENSION_NAMES),
			pEnabledFeatures        = &required_device_features,
		}
		if res := vk.CreateDevice(state.physical_device, &device_create_info, nil, &state.device);
		   res != vk.Result.SUCCESS {
			panic("create logical device failed")
		}
		// we are only grabbing one queue per queue family
		vk.GetDeviceQueue(
			state.device,
			state.graphics_queue_family_index,
			0,
			&state.graphics_queue,
		)
		vk.GetDeviceQueue(state.device, state.present_queue_family_index, 0, &state.present_queue)
	}

	{ 	// select physical device surface format
		supported_surface_formats := get_physical_device_surface_formats(
			state.physical_device,
			state.surface,
		)
		format_selected := false
		for available_format in supported_surface_formats {
			// select preferred format if it's supported, else just take the first supported format
			if available_format.format == vk.Format.B8G8R8A8_SRGB &&
			   available_format.colorSpace == vk.ColorSpaceKHR.SRGB_NONLINEAR {
				state.swapchain_format = available_format
				format_selected = true
				break
			}
		}
		if !format_selected {
			state.swapchain_format = supported_surface_formats[0]
		}
		delete(supported_surface_formats)

	}

	{ 	// select physical device surface present mode
		supported_surface_present_modes := get_physical_device_surface_present_modes(
			state.physical_device,
			state.surface,
		)
		mode_selected := false
		for available_mode in supported_surface_present_modes {
			// select preferred present mode if it's supported, else just take FIFO because it's guaranteed to be supported
			if available_mode == vk.PresentModeKHR.MAILBOX {
				state.present_mode = available_mode
				mode_selected = true
				break
			}
		}
		if !mode_selected {
			state.present_mode = vk.PresentModeKHR.FIFO
		}
		delete(supported_surface_present_modes)
	}

	set_swapchain_extent(&state)
	setup_new_swapchain(&state)

	{ 	// create shader modules
		shader_code_vertex, vert_shader_read_ok := os.read_entire_file("vert.spv")
		if !vert_shader_read_ok {
			panic("read vertex shader code failed")
		}
		shader_code_fragment, frag_shader_read_ok := os.read_entire_file("frag.spv")
		if !frag_shader_read_ok {
			panic("read fragment shader code failed")
		}
		create_info_vertex := vk.ShaderModuleCreateInfo {
			sType    = .SHADER_MODULE_CREATE_INFO,
			pCode    = cast(^u32)raw_data(shader_code_vertex),
			codeSize = len(shader_code_vertex),
		}
		create_info_fragment := vk.ShaderModuleCreateInfo {
			sType    = .SHADER_MODULE_CREATE_INFO,
			pCode    = cast(^u32)raw_data(shader_code_fragment),
			codeSize = len(shader_code_fragment),
		}
		if res := vk.CreateShaderModule(
			state.device,
			&create_info_vertex,
			nil,
			&state.shader_module_vertex,
		); res != vk.Result.SUCCESS {
			panic("failed to create vertex shader module")
		}
		if res := vk.CreateShaderModule(
			state.device,
			&create_info_fragment,
			nil,
			&state.shader_module_fragment,
		); res != vk.Result.SUCCESS {
			panic("failed to create fragment shader module")
		}
	}

	{ 	// create descriptor sets for combined image sampler
		descriptor_set_layout_binding_sampler := vk.DescriptorSetLayoutBinding {
			binding            = 0,
			descriptorType     = .COMBINED_IMAGE_SAMPLER,
			descriptorCount    = 1,
			pImmutableSamplers = nil,
			stageFlags         = {.FRAGMENT},
		}
		descriptor_set_bindings := []vk.DescriptorSetLayoutBinding {
			descriptor_set_layout_binding_sampler,
		}
		descriptor_set_layout_create_info := vk.DescriptorSetLayoutCreateInfo {
			sType        = .DESCRIPTOR_SET_LAYOUT_CREATE_INFO,
			bindingCount = cast(u32)len(descriptor_set_bindings),
			pBindings    = raw_data(descriptor_set_bindings),
		}
		if res := vk.CreateDescriptorSetLayout(
			state.device,
			&descriptor_set_layout_create_info,
			nil,
			&state.descriptor_set_layout,
		); res != .SUCCESS {
			panic("failed to create descriptor set layout")
		}
	}

	{ 	// create graphics pipeline
		vertex_shader_stage_create_info := vk.PipelineShaderStageCreateInfo {
			sType  = .PIPELINE_SHADER_STAGE_CREATE_INFO,
			stage  = {.VERTEX},
			pName  = "main",
			module = state.shader_module_vertex,
		}
		fragment_shader_stage_create_info := vk.PipelineShaderStageCreateInfo {
			sType  = .PIPELINE_SHADER_STAGE_CREATE_INFO,
			stage  = {.FRAGMENT},
			pName  = "main",
			module = state.shader_module_fragment,
		}
		shader_stage_create_infos := []vk.PipelineShaderStageCreateInfo {
			vertex_shader_stage_create_info,
			fragment_shader_stage_create_info,
		}
		dynamic_states := []vk.DynamicState{.VIEWPORT, .SCISSOR}
		dynamic_state_create_info := vk.PipelineDynamicStateCreateInfo {
			sType             = .PIPELINE_DYNAMIC_STATE_CREATE_INFO,
			dynamicStateCount = cast(u32)len(dynamic_states),
			pDynamicStates    = raw_data(dynamic_states),
		}
		vertex_input_state_create_info := vk.PipelineVertexInputStateCreateInfo {
			sType                           = .PIPELINE_VERTEX_INPUT_STATE_CREATE_INFO,
			vertexBindingDescriptionCount   = 1,
			pVertexBindingDescriptions      = &vertex_input_binding_description,
			vertexAttributeDescriptionCount = cast(u32)len(vertex_input_attribute_descriptions),
			pVertexAttributeDescriptions    = raw_data(vertex_input_attribute_descriptions),
		}
		input_assembly_state_create_info := vk.PipelineInputAssemblyStateCreateInfo {
			sType                  = .PIPELINE_INPUT_ASSEMBLY_STATE_CREATE_INFO,
			topology               = .TRIANGLE_LIST,
			primitiveRestartEnable = false,
		}
		viewport := vk.Viewport {
			x        = 0,
			y        = 0,
			width    = cast(f32)state.swapchain_extent.width,
			height   = cast(f32)state.swapchain_extent.height,
			minDepth = 0,
			maxDepth = 1,
		}
		scissor := vk.Rect2D {
			offset = {0, 0},
			extent = state.swapchain_extent,
		}
		pipeline_viewport_state_create_info := vk.PipelineViewportStateCreateInfo {
			sType         = .PIPELINE_VIEWPORT_STATE_CREATE_INFO,
			viewportCount = 1,
			scissorCount  = 1,
		}
		pipeline_rasterization_state_create_info := vk.PipelineRasterizationStateCreateInfo {
			sType                   = .PIPELINE_RASTERIZATION_STATE_CREATE_INFO,
			depthClampEnable        = false,
			rasterizerDiscardEnable = false,
			polygonMode             = .FILL,
			lineWidth               = 1,
			cullMode                = {.BACK},
			frontFace               = .CLOCKWISE,
			depthBiasEnable         = false,
		}
		pipeline_multisample_state_create_info := vk.PipelineMultisampleStateCreateInfo {
			sType                = .PIPELINE_MULTISAMPLE_STATE_CREATE_INFO,
			sampleShadingEnable  = false,
			rasterizationSamples = {._1},
		}
		pipeline_color_blend_attachment_state := vk.PipelineColorBlendAttachmentState {
			colorWriteMask = {.R, .G, .B, .A},
			blendEnable    = false,
		}
		pipeline_color_blend_state_create_info := vk.PipelineColorBlendStateCreateInfo {
			sType           = .PIPELINE_COLOR_BLEND_STATE_CREATE_INFO,
			logicOpEnable   = false,
			attachmentCount = 1,
			pAttachments    = &pipeline_color_blend_attachment_state,
		}
		pipeline_layout_create_info := vk.PipelineLayoutCreateInfo {
			sType          = .PIPELINE_LAYOUT_CREATE_INFO,
			setLayoutCount = 1,
			pSetLayouts    = &state.descriptor_set_layout,
		}
		if res := vk.CreatePipelineLayout(
			state.device,
			&pipeline_layout_create_info,
			nil,
			&state.pipeline_layout,
		); res != vk.Result.SUCCESS {
			panic("create pipeline layout failed")
		}
		color_attachment_description := vk.AttachmentDescription {
			format         = state.swapchain_format.format,
			samples        = {._1},
			loadOp         = .CLEAR,
			storeOp        = .STORE,
			stencilLoadOp  = .DONT_CARE,
			stencilStoreOp = .DONT_CARE,
			initialLayout  = .UNDEFINED,
			finalLayout    = .PRESENT_SRC_KHR,
		}
		color_attachment_ref := vk.AttachmentReference {
			attachment = 0, // this matches the (location = 0) in our fragment shader output
			layout     = .COLOR_ATTACHMENT_OPTIMAL,
		}
		subpass_description := vk.SubpassDescription {
			colorAttachmentCount = 1,
			pColorAttachments    = &color_attachment_ref,
		}
		subpass_dependency := vk.SubpassDependency {
			srcSubpass    = vk.SUBPASS_EXTERNAL,
			dstSubpass    = 0,
			srcStageMask  = {.COLOR_ATTACHMENT_OUTPUT},
			srcAccessMask = {},
			dstStageMask  = {.COLOR_ATTACHMENT_OUTPUT},
			dstAccessMask = {.COLOR_ATTACHMENT_WRITE},
		}
		render_pass_create_info := vk.RenderPassCreateInfo {
			sType           = .RENDER_PASS_CREATE_INFO,
			attachmentCount = 1,
			pAttachments    = &color_attachment_description,
			subpassCount    = 1,
			pSubpasses      = &subpass_description,
			dependencyCount = 1,
			pDependencies   = &subpass_dependency,
		}
		if res := vk.CreateRenderPass(
			state.device,
			&render_pass_create_info,
			nil,
			&state.render_pass,
		); res != vk.Result.SUCCESS {
			panic("create render pass failed")
		}
		graphics_pipeline_create_info := vk.GraphicsPipelineCreateInfo {
			sType               = .GRAPHICS_PIPELINE_CREATE_INFO,
			stageCount          = 2,
			pStages             = raw_data(shader_stage_create_infos),
			pVertexInputState   = &vertex_input_state_create_info,
			pInputAssemblyState = &input_assembly_state_create_info,
			pViewportState      = &pipeline_viewport_state_create_info,
			pRasterizationState = &pipeline_rasterization_state_create_info,
			pMultisampleState   = &pipeline_multisample_state_create_info,
			pDepthStencilState  = nil,
			pColorBlendState    = &pipeline_color_blend_state_create_info,
			pDynamicState       = &dynamic_state_create_info,
			layout              = state.pipeline_layout,
			renderPass          = state.render_pass,
			subpass             = 0,
		}
		if res := vk.CreateGraphicsPipelines(
			state.device,
			0,
			1,
			&graphics_pipeline_create_info,
			nil,
			&state.graphics_pipeline,
		); res != .SUCCESS {
			panic("create graphics pipeline failed")
		}
		vk.DestroyShaderModule(state.device, state.shader_module_vertex, nil)
		vk.DestroyShaderModule(state.device, state.shader_module_fragment, nil)
		state.shader_module_vertex = 0
		state.shader_module_fragment = 0
	}

	setup_new_framebuffers(&state)

	{ 	// create command pool
		command_pool_create_info := vk.CommandPoolCreateInfo {
			sType            = .COMMAND_POOL_CREATE_INFO,
			flags            = {.RESET_COMMAND_BUFFER},
			queueFamilyIndex = state.graphics_queue_family_index,
		}
		if res := vk.CreateCommandPool(
			state.device,
			&command_pool_create_info,
			nil,
			&state.command_pool,
		); res != .SUCCESS {
			panic("create command pool failed")
		}
	}

	{ 	// create texture image
		width, height, channel_count: i32
		pixels := stbi.load("./textures.png", &width, &height, &channel_count, 0)
		if pixels == nil {
			panic("failed to load image data")
		}
		if channel_count != 4 {
			panic("ASSERT: I've assumed 4 channel input images")
		}
		image_size := cast(vk.DeviceSize)(width * height * 4)
		staging_buffer, staging_buffer_memory := create_buffer(
			&state,
			image_size,
			{.TRANSFER_SRC},
			{.HOST_VISIBLE, .HOST_COHERENT},
		)
		defer {
			vk.DestroyBuffer(state.device, staging_buffer, nil)
			vk.FreeMemory(state.device, staging_buffer_memory, nil)
		}
		staging_buffer_data: rawptr
		vk.MapMemory(state.device, staging_buffer_memory, 0, image_size, {}, &staging_buffer_data)
		intrinsics.mem_copy_non_overlapping(staging_buffer_data, pixels, image_size)
		vk.UnmapMemory(state.device, staging_buffer_memory)
		texture_image_create_info := vk.ImageCreateInfo {
			sType = .IMAGE_CREATE_INFO,
			imageType = .D2,
			extent = {width = cast(u32)width, height = cast(u32)height, depth = 1},
			mipLevels = 1,
			arrayLayers = 1,
			format = .R8G8B8A8_SRGB,
			tiling = .OPTIMAL,
			initialLayout = .UNDEFINED,
			usage = {.TRANSFER_DST, .SAMPLED},
			sharingMode = .EXCLUSIVE,
			samples = {._1},
		}
		if res := vk.CreateImage(
			state.device,
			&texture_image_create_info,
			nil,
			&state.texture_image,
		); res != .SUCCESS {
			panic("failed to create texture image")
		}
		image_memory_requirements: vk.MemoryRequirements
		vk.GetImageMemoryRequirements(
			state.device,
			state.texture_image,
			&image_memory_requirements,
		)
		image_allocate_info := vk.MemoryAllocateInfo {
			sType           = .MEMORY_ALLOCATE_INFO,
			allocationSize  = image_memory_requirements.size,
			memoryTypeIndex = find_memory_type(
				&state,
				image_memory_requirements.memoryTypeBits,
				{.DEVICE_LOCAL},
			),
		}
		if res := vk.AllocateMemory(
			state.device,
			&image_allocate_info,
			nil,
			&state.texture_image_memory,
		); res != .SUCCESS {
			panic("failed to allocate image memory")
		}
		vk.BindImageMemory(state.device, state.texture_image, state.texture_image_memory, 0)
		transition_image_layout(
			&state,
			state.texture_image,
			.R8G8B8A8_SRGB,
			.UNDEFINED,
			.TRANSFER_DST_OPTIMAL,
		)
		copy_buffer_to_image(
			&state,
			staging_buffer,
			state.texture_image,
			cast(u32)width,
			cast(u32)height,
		)
		transition_image_layout(
			&state,
			state.texture_image,
			.R8G8B8A8_SRGB,
			.TRANSFER_DST_OPTIMAL,
			.SHADER_READ_ONLY_OPTIMAL,
		)
	}

	{ 	// create texture image view
		image_view_create_info := vk.ImageViewCreateInfo {
			sType = .IMAGE_VIEW_CREATE_INFO,
			image = state.texture_image,
			viewType = .D2,
			format = .R8G8B8A8_SRGB,
			subresourceRange = {
				aspectMask = {.COLOR},
				baseMipLevel = 0,
				levelCount = 1,
				baseArrayLayer = 0,
				layerCount = 1,
			},
		}
		if res := vk.CreateImageView(
			state.device,
			&image_view_create_info,
			nil,
			&state.texture_image_view,
		); res != .SUCCESS {
			panic("failed to create texture image view")
		}
	}

	{ 	// create texture sampler
		physical_device_properties: vk.PhysicalDeviceProperties
		vk.GetPhysicalDeviceProperties(state.physical_device, &physical_device_properties)
		sampler_create_info := vk.SamplerCreateInfo {
			sType                   = .SAMPLER_CREATE_INFO,
			magFilter               = .LINEAR,
			minFilter               = .LINEAR,
			addressModeU            = .REPEAT,
			addressModeV            = .REPEAT,
			addressModeW            = .REPEAT,
			anisotropyEnable        = true,
			maxAnisotropy           = physical_device_properties.limits.maxSamplerAnisotropy,
			borderColor             = .INT_OPAQUE_BLACK,
			unnormalizedCoordinates = true,
			compareEnable           = false,
			compareOp               = .ALWAYS,
			mipmapMode              = .LINEAR,
			mipLodBias              = 0,
			minLod                  = 0,
			maxLod                  = 0,
		}
		if res := vk.CreateSampler(
			state.device,
			&sampler_create_info,
			nil,
			&state.texture_sampler,
		); res != .SUCCESS {
			panic("failed to create texture sampler")
		}
	}

	for i in 0 ..< MAX_FRAMES_IN_FLIGHT {
		state.vertex_buffers[i], state.vertex_buffers_memory[i] = create_buffer(
			&state,
			VERTEX_BUFFER_SIZE,
			{.VERTEX_BUFFER},
			{.HOST_VISIBLE, .HOST_CACHED},
		)
		vk.MapMemory(
			state.device,
			state.vertex_buffers_memory[i],
			0,
			VERTEX_BUFFER_SIZE,
			{},
			&state.vertex_buffers_mapped[i],
		)

		state.index_buffers[i], state.index_buffers_memory[i] = create_buffer(
			&state,
			INDEX_BUFFER_SIZE,
			{.INDEX_BUFFER},
			{.HOST_VISIBLE, .HOST_CACHED},
		)
		vk.MapMemory(
			state.device,
			state.index_buffers_memory[i],
			0,
			INDEX_BUFFER_SIZE,
			{},
			&state.index_buffers_mapped[i],
		)
	}

	{ 	// create descriptor pool
		descriptor_pool_size_sampler := vk.DescriptorPoolSize {
			type            = .COMBINED_IMAGE_SAMPLER,
			descriptorCount = MAX_FRAMES_IN_FLIGHT,
		}
		pool_sizes := []vk.DescriptorPoolSize {
			descriptor_pool_size_sampler,
		}
		descriptor_pool_create_info := vk.DescriptorPoolCreateInfo {
			sType         = .DESCRIPTOR_POOL_CREATE_INFO,
			poolSizeCount = cast(u32)len(pool_sizes),
			pPoolSizes    = raw_data(pool_sizes),
			maxSets       = MAX_FRAMES_IN_FLIGHT,
		}
		if res := vk.CreateDescriptorPool(
			state.device,
			&descriptor_pool_create_info,
			nil,
			&state.descriptor_pool,
		); res != .SUCCESS {
			panic("failed to create descriptor pool")
		}
	}

	{ 	// allocate and configure descriptor sets
		layouts := [MAX_FRAMES_IN_FLIGHT]vk.DescriptorSetLayout {
			state.descriptor_set_layout,
			state.descriptor_set_layout,
		}
		allocate_info := vk.DescriptorSetAllocateInfo {
			sType              = .DESCRIPTOR_SET_ALLOCATE_INFO,
			descriptorPool     = state.descriptor_pool,
			descriptorSetCount = MAX_FRAMES_IN_FLIGHT,
			pSetLayouts        = &layouts[0],
		}
		if res := vk.AllocateDescriptorSets(
			state.device,
			&allocate_info,
			&state.descriptor_sets[0],
		); res != .SUCCESS {
			panic("failed to allocate descriptor sets")
		}

		for i in 0 ..< MAX_FRAMES_IN_FLIGHT {
			descriptor_image_info := vk.DescriptorImageInfo {
				imageLayout = .SHADER_READ_ONLY_OPTIMAL,
				imageView   = state.texture_image_view,
				sampler     = state.texture_sampler,
			}
			descriptor_write_sampler := vk.WriteDescriptorSet {
				sType           = .WRITE_DESCRIPTOR_SET,
				dstSet          = state.descriptor_sets[i],
				dstBinding      = 0,
				dstArrayElement = 0,
				descriptorType  = .COMBINED_IMAGE_SAMPLER,
				descriptorCount = 1,
				pImageInfo      = &descriptor_image_info,
			}
			descriptor_writes := []vk.WriteDescriptorSet{descriptor_write_sampler}
			vk.UpdateDescriptorSets(
				state.device,
				cast(u32)len(descriptor_writes),
				raw_data(descriptor_writes),
				0,
				nil,
			)
		}
	}

	{ 	// create command buffers
		command_buffer_allocate_info := vk.CommandBufferAllocateInfo {
			sType              = .COMMAND_BUFFER_ALLOCATE_INFO,
			commandPool        = state.command_pool,
			level              = .PRIMARY,
			commandBufferCount = len(state.command_buffers),
		}
		if res := vk.AllocateCommandBuffers(
			state.device,
			&command_buffer_allocate_info,
			&state.command_buffers[0],
		); res != .SUCCESS {
			panic("allocate command buffers failed")
		}
	}

	{ 	// create sync objects
		semaphore_create_info := vk.SemaphoreCreateInfo {
			sType = .SEMAPHORE_CREATE_INFO,
		}
		fence_create_info := vk.FenceCreateInfo {
			sType = .FENCE_CREATE_INFO,
			flags = {.SIGNALED},
		}
		for i in 0 ..< MAX_FRAMES_IN_FLIGHT {
			if res := vk.CreateSemaphore(
				state.device,
				&semaphore_create_info,
				nil,
				&state.sync_semaphores_image_available[i],
			); res != .SUCCESS {
				panic("create image available semaphore failed")
			}
			if res := vk.CreateSemaphore(
				state.device,
				&semaphore_create_info,
				nil,
				&state.sync_semaphores_render_finished[i],
			); res != .SUCCESS {
				panic("create render finished semaphore failed")
			}
			if res := vk.CreateFence(
				state.device,
				&fence_create_info,
				nil,
				&state.sync_fences_in_flight[i],
			); res != .SUCCESS {
				panic("create in-flight fence failed")
			}
		}
	}
	return state
}

teardown_renderer :: proc(state: ^RendererState) {
	for i in 0 ..< MAX_FRAMES_IN_FLIGHT {
		vk.DestroySemaphore(state.device, state.sync_semaphores_image_available[i], nil)
		vk.DestroySemaphore(state.device, state.sync_semaphores_render_finished[i], nil)
		vk.DestroyFence(state.device, state.sync_fences_in_flight[i], nil)
	}
	vk.DestroyDescriptorPool(state.device, state.descriptor_pool, nil)
	for i in 0 ..< MAX_FRAMES_IN_FLIGHT {
		vk.DestroyBuffer(state.device, state.index_buffers[i], nil)
		vk.FreeMemory(state.device, state.index_buffers_memory[i], nil)
		vk.DestroyBuffer(state.device, state.vertex_buffers[i], nil)
		vk.FreeMemory(state.device, state.vertex_buffers_memory[i], nil)
	}
	vk.DestroySampler(state.device, state.texture_sampler, nil)
	vk.DestroyImageView(state.device, state.texture_image_view, nil)
	vk.DestroyImage(state.device, state.texture_image, nil)
	vk.FreeMemory(state.device, state.texture_image_memory, nil)
	vk.DestroyCommandPool(state.device, state.command_pool, nil)
	teardown_swapchain(state)
	vk.DestroyPipeline(state.device, state.graphics_pipeline, nil)
	vk.DestroyPipelineLayout(state.device, state.pipeline_layout, nil)
	vk.DestroyRenderPass(state.device, state.render_pass, nil)
	vk.DestroyDescriptorSetLayout(state.device, state.descriptor_set_layout, nil)
	vk.DestroyDevice(state.device, nil)
	vk.DestroySurfaceKHR(state.instance, state.surface, nil)
	vk.DestroyInstance(state.instance, nil)
	glfw.DestroyWindow(state.window)
	glfw.Terminate()
}

teardown_swapchain :: proc(state: ^RendererState) {
	for framebuffer in state.swapchain_framebuffers {
		vk.DestroyFramebuffer(state.device, framebuffer, nil)
	}
	delete(state.swapchain_framebuffers)
	for image_view in state.swapchain_image_views {
		vk.DestroyImageView(state.device, image_view, nil)
	}
	delete(state.swapchain_image_views)
	delete(state.swapchain_images)
	vk.DestroySwapchainKHR(state.device, state.swapchain, nil)
}

recreate_swapchain :: proc(state: ^RendererState) {
	// handle minimization
	width, height := glfw.GetFramebufferSize(state.window)
	for width == 0 || height == 0 {
		width, height = glfw.GetFramebufferSize(state.window)
		glfw.WaitEvents()
	}

	vk.DeviceWaitIdle(state.device)
	teardown_swapchain(state)
	set_swapchain_extent(state)
	setup_new_swapchain(state)
	setup_new_framebuffers(state)
}

set_swapchain_extent :: proc(state: ^RendererState) {
	if res := vk.GetPhysicalDeviceSurfaceCapabilitiesKHR(
		state.physical_device,
		state.surface,
		&state.surface_capabilities,
	); res != vk.Result.SUCCESS {
		panic("get physical device surface capabilities failed")
	}
	// special value, indicates size will be determined by extent of a swapchain targeting the surface
	if state.surface_capabilities.currentExtent.width == max(u32) {
		width, height := glfw.GetFramebufferSize(state.window)
		extent: vk.Extent2D = {
			width  = clamp(
				cast(u32)width,
				state.surface_capabilities.minImageExtent.width,
				state.surface_capabilities.maxImageExtent.width,
			),
			height = clamp(
				cast(u32)height,
				state.surface_capabilities.minImageExtent.height,
				state.surface_capabilities.maxImageExtent.height,
			),
		}
		state.swapchain_extent = extent
	} else {
		// default case, set swapchain extent to match the screens current extent
		state.swapchain_extent = state.surface_capabilities.currentExtent
	}
}

setup_new_swapchain :: proc(state: ^RendererState) {
	// create swapchain
	swapchain_create_info := vk.SwapchainCreateInfoKHR {
		sType            = .SWAPCHAIN_CREATE_INFO_KHR,
		surface          = state.surface,
		oldSwapchain     = 0, // VK_NULL_HANDLE
		imageFormat      = state.swapchain_format.format,
		imageColorSpace  = state.swapchain_format.colorSpace,
		presentMode      = state.present_mode,
		imageExtent      = state.swapchain_extent,
		minImageCount    = state.surface_capabilities.minImageCount + 1,
		imageUsage       = {.COLOR_ATTACHMENT},
		imageArrayLayers = 1,
		imageSharingMode = .EXCLUSIVE,
		compositeAlpha   = {.OPAQUE},
		clipped          = true,
		preTransform     = state.surface_capabilities.currentTransform,
	}
	if res := vk.CreateSwapchainKHR(state.device, &swapchain_create_info, nil, &state.swapchain);
	   res != vk.Result.SUCCESS {
		panic("create swapchain failed")
	}

	// get swapchain images
	state.swapchain_images = get_swapchain_images(state.device, state.swapchain)

	// create swapchain image views
	state.swapchain_image_views = make([]vk.ImageView, len(state.swapchain_images))
	for i in 0 ..< len(state.swapchain_images) {
		image_view_create_info := vk.ImageViewCreateInfo {
			sType = .IMAGE_VIEW_CREATE_INFO,
			image = state.swapchain_images[i],
			viewType = vk.ImageViewType.D2,
			format = state.swapchain_format.format,
			components = {r = .IDENTITY, g = .IDENTITY, b = .IDENTITY, a = .IDENTITY},
			subresourceRange = {
				aspectMask = {.COLOR},
				baseMipLevel = 0,
				levelCount = 1,
				baseArrayLayer = 0,
				layerCount = 1,
			},
		}
		if res := vk.CreateImageView(
			state.device,
			&image_view_create_info,
			nil,
			&state.swapchain_image_views[i],
		); res != vk.Result.SUCCESS {
			panic("create image view failed")
		}
	}
}

get_swapchain_images :: proc(device: vk.Device, swapchain: vk.SwapchainKHR) -> []vk.Image {
	count: u32
	vk.GetSwapchainImagesKHR(device, swapchain, &count, nil)
	swapchain_images := make([]vk.Image, count)
	vk.GetSwapchainImagesKHR(device, swapchain, &count, raw_data(swapchain_images))
	return swapchain_images
}

setup_new_framebuffers :: proc(state: ^RendererState) {
	state.swapchain_framebuffers = make([]vk.Framebuffer, len(state.swapchain_image_views))
	for i in 0 ..< len(state.swapchain_image_views) {
		framebuffer_create_info := vk.FramebufferCreateInfo {
			sType           = .FRAMEBUFFER_CREATE_INFO,
			renderPass      = state.render_pass,
			attachmentCount = 1,
			pAttachments    = &state.swapchain_image_views[i],
			width           = state.swapchain_extent.width,
			height          = state.swapchain_extent.height,
			layers          = 1,
		}
		if res := vk.CreateFramebuffer(
			state.device,
			&framebuffer_create_info,
			nil,
			&state.swapchain_framebuffers[i],
		); res != .SUCCESS {
			panic("create framebuffer failed")
		}
	}
}

check_validation_layer_support :: proc() -> bool {
	count: u32
	vk.EnumerateInstanceLayerProperties(&count, nil)
	available_layers := make([]vk.LayerProperties, count)
	defer delete(available_layers)
	if vk.EnumerateInstanceLayerProperties(&count, raw_data(available_layers)) !=
	   vk.Result.SUCCESS {
		panic("enumerate instance layer properties failed")
	}
	for required_layer_name in REQUIRED_LAYER_NAMES {
		found := false
		for &available_layer in available_layers {
			available_layer_name := cast(cstring)&available_layer.layerName[0]
			if required_layer_name == available_layer_name {
				found = true
			}
		}
		if !found {return false}
	}
	return true
}

check_extension_support :: proc(device: vk.PhysicalDevice) -> bool {
	count: u32
	vk.EnumerateDeviceExtensionProperties(device, nil, &count, nil)
	extension_properties := make([]vk.ExtensionProperties, count)
	defer delete(extension_properties)
	vk.EnumerateDeviceExtensionProperties(device, nil, &count, raw_data(extension_properties))
	for required_extension_name in REQUIRED_EXTENSION_NAMES {
		found := false
		for available_extension_properties in extension_properties {
			available_extension_name := available_extension_properties.extensionName
			if cast(cstring)&available_extension_name[0] == required_extension_name {
				found = true
			}
		}
		if !found {
			return false
		}
	}
	return true
}

get_physical_devices :: proc(instance: vk.Instance) -> []vk.PhysicalDevice {
	count: u32
	vk.EnumeratePhysicalDevices(instance, &count, nil)
	if count == 0 {
		panic("failed to find a Vulkan compatible device")
	}
	physical_devices := make([]vk.PhysicalDevice, count)
	if vk.EnumeratePhysicalDevices(instance, &count, raw_data(physical_devices)) !=
	   vk.Result.SUCCESS {
		panic("enumerate physical devices failed")
	}
	return physical_devices
}

get_queue_family_properties :: proc(
	physical_device: vk.PhysicalDevice,
) -> []vk.QueueFamilyProperties {
	count: u32
	vk.GetPhysicalDeviceQueueFamilyProperties(physical_device, &count, nil)
	queue_family_properties := make([]vk.QueueFamilyProperties, count)
	vk.GetPhysicalDeviceQueueFamilyProperties(
		physical_device,
		&count,
		raw_data(queue_family_properties),
	)
	return queue_family_properties
}

get_physical_device_surface_formats :: proc(
	physical_device: vk.PhysicalDevice,
	surface: vk.SurfaceKHR,
) -> []vk.SurfaceFormatKHR {
	count: u32
	vk.GetPhysicalDeviceSurfaceFormatsKHR(physical_device, surface, &count, nil)
	if count == 0 {
		panic("found no physical device surface formats")
	}
	supported_surface_formats := make([]vk.SurfaceFormatKHR, count)
	if res := vk.GetPhysicalDeviceSurfaceFormatsKHR(
		physical_device,
		surface,
		&count,
		raw_data(supported_surface_formats),
	); res != vk.Result.SUCCESS {
		panic("get physical device surface formats failed")
	}
	return supported_surface_formats
}

get_physical_device_surface_present_modes :: proc(
	physical_device: vk.PhysicalDevice,
	surface: vk.SurfaceKHR,
) -> []vk.PresentModeKHR {
	count: u32
	vk.GetPhysicalDeviceSurfacePresentModesKHR(physical_device, surface, &count, nil)
	if count == 0 {
		panic("found no physical device surface present modes")
	}
	supported_surface_present_modes := make([]vk.PresentModeKHR, count)
	if res := vk.GetPhysicalDeviceSurfacePresentModesKHR(
		physical_device,
		surface,
		&count,
		raw_data(supported_surface_present_modes),
	); res != vk.Result.SUCCESS {
		panic("get physical device surface present modes failed")
	}
	return supported_surface_present_modes
}

check_feature_support :: proc(device: vk.PhysicalDevice) -> b32 {
	supported_features: vk.PhysicalDeviceFeatures
	vk.GetPhysicalDeviceFeatures(device, &supported_features)
	return supported_features.samplerAnisotropy
}

create_buffer :: proc(
	state: ^RendererState,
	size: vk.DeviceSize,
	usage: vk.BufferUsageFlags,
	memory_properties: vk.MemoryPropertyFlags,
) -> (
	buffer: vk.Buffer,
	buffer_memory: vk.DeviceMemory,
) {
	// create buffer
	buffer_create_info := vk.BufferCreateInfo {
		sType       = .BUFFER_CREATE_INFO,
		size        = size,
		usage       = usage,
		sharingMode = .EXCLUSIVE,
	}
	if res := vk.CreateBuffer(state.device, &buffer_create_info, nil, &buffer); res != .SUCCESS {
		panic("create buffer failed")
	}
	// allocate and bind memory
	buffer_memory_requirements: vk.MemoryRequirements
	vk.GetBufferMemoryRequirements(state.device, buffer, &buffer_memory_requirements)
	buffer_allocate_info := vk.MemoryAllocateInfo {
		sType           = .MEMORY_ALLOCATE_INFO,
		allocationSize  = buffer_memory_requirements.size,
		memoryTypeIndex = find_memory_type(
			state,
			buffer_memory_requirements.memoryTypeBits,
			memory_properties,
		),
	}
	if res := vk.AllocateMemory(state.device, &buffer_allocate_info, nil, &buffer_memory);
	   res != .SUCCESS {
		panic("failed to allocate buffer memory")
	}
	vk.BindBufferMemory(state.device, buffer, buffer_memory, 0)

	return buffer, buffer_memory
}

copy_buffer :: proc(state: ^RendererState, src: vk.Buffer, dst: vk.Buffer, size: vk.DeviceSize) {
	temp_command_buffer := begin_single_time_commands(state)
	buffer_copy_info := vk.BufferCopy {
		size = size,
	}
	vk.CmdCopyBuffer(temp_command_buffer, src, dst, 1, &buffer_copy_info)
	end_single_time_commands(state, &temp_command_buffer)
}

find_memory_type :: proc(
	state: ^RendererState,
	type_filter: u32,
	properties: vk.MemoryPropertyFlags,
) -> u32 {
	physical_device_memory_properties: vk.PhysicalDeviceMemoryProperties
	vk.GetPhysicalDeviceMemoryProperties(state.physical_device, &physical_device_memory_properties)
	for i in 0 ..< physical_device_memory_properties.memoryTypeCount {
		if type_filter & (1 << i) != 0 &&
		   physical_device_memory_properties.memoryTypes[i].propertyFlags >= properties {
			return i
		}
	}
	panic("failed to find suitable memory type")
}

begin_single_time_commands :: proc(state: ^RendererState) -> vk.CommandBuffer {
	command_buffer_allocate_info := vk.CommandBufferAllocateInfo {
		sType              = .COMMAND_BUFFER_ALLOCATE_INFO,
		level              = .PRIMARY,
		commandPool        = state.command_pool,
		commandBufferCount = 1,
	}
	temp_command_buffer: vk.CommandBuffer
	if res := vk.AllocateCommandBuffers(
		state.device,
		&command_buffer_allocate_info,
		&temp_command_buffer,
	); res != .SUCCESS {
		panic("failed to allocate temporary buffer for image transition")
	}
	command_buffer_begin_info := vk.CommandBufferBeginInfo {
		sType = .COMMAND_BUFFER_BEGIN_INFO,
		flags = {.ONE_TIME_SUBMIT},
	}
	if res := vk.BeginCommandBuffer(temp_command_buffer, &command_buffer_begin_info);
	   res != .SUCCESS {
		panic("failed to begin temporary command buffer for image transition")
	}
	return temp_command_buffer
}

end_single_time_commands :: proc(state: ^RendererState, temp_command_buffer: ^vk.CommandBuffer) {
	vk.EndCommandBuffer(temp_command_buffer^)
	submit_info := vk.SubmitInfo {
		sType              = .SUBMIT_INFO,
		commandBufferCount = 1,
		pCommandBuffers    = temp_command_buffer,
	}
	vk.QueueSubmit(state.graphics_queue, 1, &submit_info, 0)
	vk.QueueWaitIdle(state.graphics_queue)
	vk.FreeCommandBuffers(state.device, state.command_pool, 1, temp_command_buffer)
}

draw_frame :: proc(using state: ^RendererState, vertices: []Vertex, indices: []u32) {
	vk.WaitForFences(device, 1, &sync_fences_in_flight[frame_index], true, max(u64))
	acquire_next_image_res := vk.AcquireNextImageKHR(
		device,
		swapchain,
		max(u64),
		sync_semaphores_image_available[frame_index],
		0,
		&swapchain_image_index,
	)
	if acquire_next_image_res == .ERROR_OUT_OF_DATE_KHR {
		recreate_swapchain(state)
		return
	}
	vk.ResetFences(device, 1, &sync_fences_in_flight[frame_index])
	vk.ResetCommandBuffer(command_buffers[frame_index], {})

	{ 	//record command buffer
		command_buffer_begin_info := vk.CommandBufferBeginInfo {
			sType = .COMMAND_BUFFER_BEGIN_INFO,
		}
		if res := vk.BeginCommandBuffer(command_buffers[frame_index], &command_buffer_begin_info);
		   res != .SUCCESS {
			panic("failed to begin recording command buffer")
		}
		clear_colour := vk.ClearValue {
			color = {float32 = {BACKGROUND_COLOUR.r, BACKGROUND_COLOUR.g, BACKGROUND_COLOUR.b, 1}},
		}
		render_pass_begin_info := vk.RenderPassBeginInfo {
			sType = .RENDER_PASS_BEGIN_INFO,
			renderPass = render_pass,
			framebuffer = swapchain_framebuffers[swapchain_image_index],
			renderArea = vk.Rect2D{offset = {0, 0}, extent = swapchain_extent},
			clearValueCount = 1,
			pClearValues = &clear_colour,
		}
		vk.CmdBeginRenderPass(command_buffers[frame_index], &render_pass_begin_info, .INLINE)
		vk.CmdBindPipeline(command_buffers[frame_index], .GRAPHICS, graphics_pipeline)
		offsets := []vk.DeviceSize{0}
		vk.CmdBindVertexBuffers(
			command_buffers[frame_index],
			0,
			1,
			&vertex_buffers[frame_index],
			raw_data(offsets),
		)
		vk.CmdBindIndexBuffer(command_buffers[frame_index], index_buffers[frame_index], 0, .UINT32)
		viewport := vk.Viewport {
			x        = 0,
			y        = 0,
			width    = cast(f32)swapchain_extent.width,
			height   = cast(f32)swapchain_extent.height,
			minDepth = 0,
			maxDepth = 1,
		}
		vk.CmdBindDescriptorSets(
			command_buffers[frame_index],
			.GRAPHICS,
			state.pipeline_layout,
			0,
			1,
			&state.descriptor_sets[frame_index],
			0,
			nil,
		)
		vk.CmdSetViewport(command_buffers[frame_index], 0, 1, &viewport)
		scissor := vk.Rect2D {
			offset = {0, 0},
			extent = swapchain_extent,
		}
		vk.CmdSetScissor(command_buffers[frame_index], 0, 1, &scissor)
		vk.CmdDrawIndexed(command_buffers[frame_index], cast(u32)len(indices), 1, 0, 0, 0)
		vk.CmdEndRenderPass(command_buffers[frame_index])
		if res := vk.EndCommandBuffer(command_buffers[frame_index]); res != .SUCCESS {
			panic("failed to record command buffer")
		}
	}

	intrinsics.mem_copy_non_overlapping(
		vertex_buffers_mapped[frame_index],
		raw_data(vertices),
		VERTEX_BUFFER_SIZE,
	)
	intrinsics.mem_copy_non_overlapping(
		index_buffers_mapped[frame_index],
		raw_data(indices),
		INDEX_BUFFER_SIZE,
	)
	wait_stages := []vk.PipelineStageFlags{{.COLOR_ATTACHMENT_OUTPUT}}
	submit_info := vk.SubmitInfo {
		sType                = .SUBMIT_INFO,
		waitSemaphoreCount   = 1,
		pWaitSemaphores      = &sync_semaphores_image_available[frame_index],
		pWaitDstStageMask    = raw_data(wait_stages),
		commandBufferCount   = 1,
		pCommandBuffers      = &command_buffers[frame_index],
		signalSemaphoreCount = 1,
		pSignalSemaphores    = &sync_semaphores_render_finished[frame_index],
	}
	queue_submit_res := vk.QueueSubmit(
		graphics_queue,
		1,
		&submit_info,
		sync_fences_in_flight[frame_index],
	)
	if queue_submit_res != .SUCCESS {
		panic("failed to submit draw command buffer")
	}
	present_info := vk.PresentInfoKHR {
		sType              = .PRESENT_INFO_KHR,
		waitSemaphoreCount = 1,
		pWaitSemaphores    = &sync_semaphores_render_finished[frame_index],
		swapchainCount     = 1,
		pSwapchains        = &swapchain,
		pImageIndices      = &swapchain_image_index,
	}
	present_res := vk.QueuePresentKHR(present_queue, &present_info)
	if present_res == .ERROR_OUT_OF_DATE_KHR ||
	   present_res == .SUBOPTIMAL_KHR ||
	   frame_buffer_resized {
		frame_buffer_resized = false
		recreate_swapchain(state)
	} else if present_res != .SUCCESS {
		panic("failed to present swapchain image")
	}

	frame_index += 1
	frame_index %= MAX_FRAMES_IN_FLIGHT
}

transition_image_layout :: proc(
	state: ^RendererState,
	image: vk.Image,
	format: vk.Format,
	old_layout: vk.ImageLayout,
	new_layout: vk.ImageLayout,
) {
	temp_command_buffer := begin_single_time_commands(state)
	memory_barrier := vk.ImageMemoryBarrier {
		sType = .IMAGE_MEMORY_BARRIER,
		oldLayout = old_layout,
		newLayout = new_layout,
		srcQueueFamilyIndex = vk.QUEUE_FAMILY_IGNORED,
		dstQueueFamilyIndex = vk.QUEUE_FAMILY_IGNORED,
		image = image,
		subresourceRange = {
			aspectMask = {.COLOR},
			baseMipLevel = 0,
			levelCount = 1,
			baseArrayLayer = 0,
			layerCount = 1,
		},
	}
	source_stage, destination_stage: vk.PipelineStageFlags
	if old_layout == .UNDEFINED && new_layout == .TRANSFER_DST_OPTIMAL {
		memory_barrier.srcAccessMask = {}
		memory_barrier.dstAccessMask = {.TRANSFER_WRITE}
		source_stage = {.TOP_OF_PIPE}
		destination_stage = {.TRANSFER}
	} else if old_layout == .TRANSFER_DST_OPTIMAL && new_layout == .SHADER_READ_ONLY_OPTIMAL {
		memory_barrier.srcAccessMask = {.TRANSFER_WRITE}
		memory_barrier.dstAccessMask = {.SHADER_READ}
		source_stage = {.TRANSFER}
		destination_stage = {.FRAGMENT_SHADER}
	} else {
		panic("unsupported layout transition")
	}
	vk.CmdPipelineBarrier(
		temp_command_buffer,
		source_stage,
		destination_stage,
		{},
		0,
		nil,
		0,
		nil,
		1,
		&memory_barrier,
	)
	end_single_time_commands(state, &temp_command_buffer)
}

copy_buffer_to_image :: proc(
	state: ^RendererState,
	buffer: vk.Buffer,
	image: vk.Image,
	width: u32,
	height: u32,
) {
	temp_command_buffer := begin_single_time_commands(state)
	buffer_image_copy := vk.BufferImageCopy {
		bufferOffset = 0,
		bufferRowLength = 0,
		bufferImageHeight = 0,
		imageSubresource = {
			aspectMask = {.COLOR},
			mipLevel = 0,
			baseArrayLayer = 0,
			layerCount = 1,
		},
		imageOffset = {0, 0, 0},
		imageExtent = {width, height, 1},
	}
	vk.CmdCopyBufferToImage(
		temp_command_buffer,
		buffer,
		image,
		.TRANSFER_DST_OPTIMAL,
		1,
		&buffer_image_copy,
	)
	end_single_time_commands(state, &temp_command_buffer)
}
