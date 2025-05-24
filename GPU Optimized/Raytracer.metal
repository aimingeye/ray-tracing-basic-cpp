#include <metal_stdlib>
using namespace metal;

struct Ray {
    float3 origin;
    float3 direction;
};

struct Sphere {
    float3 center;
    float radius;
    float radius2;
    float3 surfaceColor;
    float3 emissionColor;
    float transparency;
    float reflection;
};

struct Camera {
    float invWidth;
    float invHeight;
    float angle;
    float aspectratio;
};

// Custom mix function (renamed to avoid conflict with Metal's built-in mix)
float customMix(float a, float b, float mixValue) {
    return b * mixValue + a * (1 - mixValue);
}

// Ray-sphere intersection
bool intersectSphere(const Ray ray, const Sphere sphere, thread float& t0, thread float& t1) {
    float3 l = sphere.center - ray.origin;
    float tca = dot(l, ray.direction);
    if (tca < 0) return false;
    float d2 = dot(l, l) - tca * tca;
    if (d2 > sphere.radius2) return false;
    float thc = sqrt(sphere.radius2 - d2);
    t0 = tca - thc;
    t1 = tca + thc;
    return true;
}

float3 trace(Ray ray, const device Sphere* spheres, int sphereCount, int depth) {
    if (depth >= 100) return float3(0); // Max recursion depth
    
    float tnear = INFINITY;
    const device Sphere* hitSphere = nullptr;
    
    // Find closest intersection
    for (int i = 0; i < sphereCount; i++) {
        float t0 = INFINITY, t1 = INFINITY;
        if (intersectSphere(ray, spheres[i], t0, t1)) {
            if (t0 < 0) t0 = t1;
            if (t0 < tnear) {
                tnear = t0;
                hitSphere = &spheres[i];
            }
        }
    }
    
    // No intersection
    if (!hitSphere) return float3(2);
    
    float3 surfaceColor = float3(0);
    float3 phit = ray.origin + ray.direction * tnear;
    float3 nhit = normalize(phit - hitSphere->center);
    
    // Offset normal based on ray direction
    bool inside = false;
    if (dot(ray.direction, nhit) > 0) {
        nhit = -nhit;
        inside = true;
    }
    
    // Handle reflection and refraction
    if ((hitSphere->transparency > 0 || hitSphere->reflection > 0) && depth < 100) {
        float facingratio = -dot(ray.direction, nhit);
        float fresneleffect = customMix(pow(1 - facingratio, 3), 1, 0.1);
        
        // Compute reflection
        float3 refldir = normalize(ray.direction - nhit * 2 * dot(ray.direction, nhit));
        Ray reflectionRay = { phit + nhit * 0.0001f, refldir };
        float3 reflection = trace(reflectionRay, spheres, sphereCount, depth + 1);
        
        float3 refraction = float3(0);
        if (hitSphere->transparency > 0) {
            float ior = 1.1f;
            float eta = inside ? ior : 1 / ior;
            float cosi = -dot(nhit, ray.direction);
            float k = 1 - eta * eta * (1 - cosi * cosi);
            
            if (k >= 0) {
                float3 refrdir = normalize(ray.direction * eta + nhit * (eta * cosi - sqrt(k)));
                Ray refractionRay = { phit - nhit * 0.0001f, refrdir };
                refraction = trace(refractionRay, spheres, sphereCount, depth + 1);
            }
        }
        
        surfaceColor = (reflection * fresneleffect + 
                       refraction * (1 - fresneleffect) * hitSphere->transparency) * 
                       hitSphere->surfaceColor;
    } else {
        // Diffuse object
        for (int i = 0; i < sphereCount; i++) {
            if (spheres[i].emissionColor.x > 0) {
                float3 transmission = float3(1);
                float3 lightDirection = normalize(spheres[i].center - phit);
                
                for (int j = 0; j < sphereCount; j++) {
                    if (i != j) {
                        float t0, t1;
                        Ray shadowRay = { phit + nhit * 0.0001f, lightDirection };
                        if (intersectSphere(shadowRay, spheres[j], t0, t1)) {
                            transmission = float3(0);
                            break;
                        }
                    }
                }
                
                surfaceColor += hitSphere->surfaceColor * transmission *
                               max(0.0f, dot(nhit, lightDirection)) * spheres[i].emissionColor;
            }
        }
    }
    
    return surfaceColor + hitSphere->emissionColor;
}

kernel void raytracerKernel(device float3* output [[buffer(0)]],
                           device const Sphere* spheres [[buffer(1)]],
                           constant int& sphereCount [[buffer(2)]],
                           constant Camera& camera [[buffer(3)]],
                           uint2 id [[thread_position_in_grid]],
                           uint2 gridSize [[threads_per_grid]]) {
    float x = float(id.x);
    float y = float(id.y);
    
    float xx = (2 * ((x + 0.5) * camera.invWidth) - 1) * camera.angle * camera.aspectratio;
    float yy = (1 - 2 * ((y + 0.5) * camera.invHeight)) * camera.angle;
    
    float3 raydir = normalize(float3(xx, yy, -1));
    Ray ray = { float3(0), raydir };
    
    output[id.y * gridSize.x + id.x] = trace(ray, spheres, sphereCount, 0);
}
