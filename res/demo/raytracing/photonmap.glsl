/*
 * Copyright LWJGL. All rights reserved.
 * License terms: http://lwjgl.org/license.php
 */
#version 430 core

/* Cube map array. A single cube map for each box. */
layout(binding = 0, rg16f) uniform imageCubeArray photonMaps;

uniform float time;
uniform int bounceCount;
uniform vec3 lightCenterPosition;
uniform float lightRadius;

struct box {
  vec3 min;
  vec3 max;
};

layout (std430, binding = 0) buffer Boxes
{
  box[] boxes;
};

#define MAX_SCENE_BOUNDS 100.0
#define EPSILON 0.0001
#define LIGHT_BASE_INTENSITY 12.0

float random(vec2 f, float time);
vec3 randomSpherePoint(vec3 rand);
vec3 randomHemispherePoint(vec3 rand, vec3 n);

struct hitinfo {
  float near;
  float far;
  int bi;
};

/*
 * We need random values every now and then.
 * So, they will be precomputed for each ray we trace and
 * can be used by any function.
 */
vec3 rand;

vec2 intersectBox(vec3 origin, vec3 dir, const box b) {
  vec3 tMin = (b.min - origin) / dir;
  vec3 tMax = (b.max - origin) / dir;
  vec3 t1 = min(tMin, tMax);
  vec3 t2 = max(tMin, tMax);
  float tNear = max(max(t1.x, t1.y), t1.z);
  float tFar = min(min(t2.x, t2.y), t2.z);
  return vec2(tNear, tFar);
}

bool intersectBoxes(vec3 origin, vec3 dir, out hitinfo info) {
  float smallest = MAX_SCENE_BOUNDS;
  bool found = false;
  int numBoxes = boxes.length();
  for (int i = 0; i < numBoxes; i++) {
    vec2 lambda = intersectBox(origin, dir, boxes[i]);
    if (lambda.x > 0.0 && lambda.x < lambda.y && lambda.x < smallest) {
      info.near = lambda.x;
      info.far = lambda.y;
      info.bi = i;
      smallest = lambda.x;
      found = true;
    }
  }
  return found;
}

int faceIndex(vec3 hit, const box b) {
  if (hit.x < b.min.x + EPSILON)
    return 1;
  else if (hit.x > b.max.x - EPSILON)
    return 0;
  else if (hit.y < b.min.y + EPSILON)
    return 3;
  else if (hit.y > b.max.y - EPSILON)
    return 2;
  else if (hit.z < b.min.z + EPSILON)
    return 5;
  else
    return 4;
}

vec3 normalForFace(int fIndex) {
  if (fIndex == 1)
    return vec3(-1.0, 0.0, 0.0);
  else if (fIndex == 0)
    return vec3(1.0, 0.0, 0.0);
  else if (fIndex == 3)
    return vec3(0.0, -1.0, 0.0);
  else if (fIndex == 2)
    return vec3(0.0, 1.0, 0.0);
  else if (fIndex == 5)
    return vec3(0.0, 0.0, -1.0);
  else
    return vec3(0.0, 0.0, 1.0);
}

vec2 texCoordForFace(vec3 hit, const box b, int fIndex) {
  if (fIndex == 0) {
    vec2 res = (hit.zy - b.min.zy) / (b.max.zy - b.min.zy);
    return vec2(1.0 - res.x, 1.0 - res.y);
  } else if (fIndex == 1) {
    vec2 res = (hit.zy - b.min.zy) / (b.max.zy - b.min.zy);
    return vec2(res.x, res.y);
    
  } else if (fIndex == 2) {
    vec2 res = (hit.xz - b.min.xz) / (b.max.xz - b.min.xz);
    return res;
  } else if (fIndex == 3) {
    vec2 res = (hit.xz - b.min.xz) / (b.max.xz - b.min.xz);
    return res;
    
  } else if (fIndex == 4) {
    vec2 res = (hit.xy - b.min.xy) / (b.max.xy - b.min.xy);
    return vec2(res.x, 1.0 - res.y);
  } else {
    vec2 res = (hit.xy - b.min.xy) / (b.max.xy - b.min.xy);
    return vec2(1.0 - res.x, res.y);
  }
}

void trace(vec3 origin, vec3 dir) {
  hitinfo i;
  vec4 accumulated = vec4(0.0);
  vec4 attenuation = vec4(1.0);
  ivec3 size = imageSize(photonMaps);
  if (intersectBoxes(origin, dir, i)) {
    box b = boxes[i.bi];
    vec3 hitPoint = origin + i.near * dir;
    int fIndex = faceIndex(hitPoint, b);
    vec3 normal = normalForFace(fIndex);
    vec3 lightToSurface = origin - hitPoint;
    float oneOverR2 = 1.0 / dot(lightToSurface, lightToSurface);
    attenuation *= dot(normal, -dir) * oneOverR2;
    origin = hitPoint + normal * EPSILON;
    dir = randomHemispherePoint(rand, normal);
    /* Write into photon map */
    vec2 texCoord = texCoordForFace(hitPoint, b, fIndex);
    ivec3 index = ivec3(texCoord * size.xy, i.bi * 6 + fIndex);
    float color = attenuation.r * LIGHT_BASE_INTENSITY;
    vec2 oldColor = imageLoad(photonMaps, index).rg;
    float numPhotons = oldColor.g;
    float blendFactor = numPhotons / (numPhotons + 1.0);
    float blended = mix(color, oldColor.r, blendFactor);
    imageStore(photonMaps, index, vec4(blended, numPhotons + 1.0, 0.0, 1.0));
  }
}

layout (local_size_x = 8, local_size_y = 8) in;

void main(void) {
  vec2 invId = vec2(gl_GlobalInvocationID.xy);
  float rand1 = random(invId, time);
  float rand2 = random(invId + vec2(641.51224, 423.178), time);
  float rand3 = random(invId - vec2(147.16414, 363.941), time);
  /* Set global 'rand' variable */
  rand = vec3(rand1, rand2, rand3);

  /* Sample random sphere point */
  vec3 randSphere = randomSpherePoint(rand);
  vec3 positionOnLight = lightCenterPosition + randSphere * lightRadius;
  vec3 lightDirection = randomHemispherePoint(rand, randSphere);
  trace(positionOnLight, lightDirection);
}
