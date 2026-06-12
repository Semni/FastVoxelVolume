uint encode (uint x, uint y, uint z)
{
    x = (x | (x << 16u)) & 0x030000FF;
    x = (x | (x << 8u)) & 0x0300F00F;
    x = (x | (x << 4u)) & 0x030C30C3;
    x = (x | (x << 2u)) & 0x09249249;

    y = (y | (y << 16u)) & 0x030000FF;
    y = (y | (y << 8u)) & 0x0300F00F;
    y = (y | (y << 4u)) & 0x030C30C3;
    y = (y | (y << 2u)) & 0x09249249;

    z = (z | (z << 16u)) & 0x030000FF;
    z = (z | (z << 8u)) & 0x0300F00F;
    z = (z | (z << 4u)) & 0x030C30C3;
    z = (z | (z << 2u)) & 0x09249249;

    return x | (y << 1) | (z << 2);
}

uint encode (uint3 xyz)
{
    return encode(xyz.x, xyz.y, xyz.z);
}

void insert (uint n, inout uint low, inout uint high)
{
    low |= n < 32 ? 1u << n : 0u;
    high |= n >= 32 && n < 64 ? 1u << (n - 32) : 0u;
    /*if(n < 32)
    {
        low = low | 1u << n;
    }
    else if(n < 64)
    {
        high = high | 1u << (n - 32);
    }*/
}

float SobelDepth(float ldc, float ldl, float ldr, float ldu, float ldd)
{
    return abs(ldl - ldc) +
        abs(ldr - ldc) +
        abs(ldu - ldc) +
        abs(ldd - ldc);
}

float SobelSampleDepth(Texture2D t, SamplerState s, float2 uv, float3 offset)
{
    float pixelCenter = t.Sample(s, uv).r;
    float pixelLeft = t.Sample(s, uv - offset.xz).r;
    float pixelRight = t.Sample(s, uv + offset.xz).r;
    float pixelUp = t.Sample(s, uv + offset.zy).r;
    float pixelDown = t.Sample(s, uv - offset.zy).r;

    return SobelDepth(pixelCenter, pixelLeft, pixelRight, pixelUp, pixelDown);
}

// Our main traversal algorithm.
bool traversal (Texture2D _MainTex, float4 _MainTex_TexelSize, float3 ray_position, float3 direction, out float3 hit_position, out uint3 hit_coord, out uint3 mask)
{
    hit_position = ray_position;
    hit_coord = uint3(0, 0, 0);

    // Division is expensive, compute and store the inverse direction once.
    float3 inverse_direction = 1.0 / direction;

    {
        // Bring the ray position into 0.0 to 1.0 space
        //ray_position += 0.5; 

        // Do our AABB intersection
        float3 t1 = -ray_position * inverse_direction;
        float3 t2 = (1.0 - ray_position) * inverse_direction;

        float3 tmins = min(t1, t2);
        float3 tmaxs = max(t1, t2);

        float tmin = max(tmins.x, max(tmins.y, tmins.z));
        float tmax = min(tmaxs.x, min(tmaxs.y, tmaxs.z));

        // If tmin is larger than tmax we know the ray doesn't hit the bounding box and can discard it.
        if(tmin > tmax) return false;

        // Clamp tmin to 0.
        tmin = max(0.0, tmin);

        // Snap the ray to the bounding box
        ray_position += direction * tmin;

        // Now we scale our position into voxel space
        ray_position *= _MainTex_TexelSize.z;

        // Initial axis setup for an immediate hit
        mask = tmins.x > tmins.y ? tmins.x > tmins.z ? uint3(1, 0, 0) : uint3(0, 0, 1) : tmins.y > tmins.z ? uint3(0, 1, 0) : uint3(0, 0, 1);
        //stepped_axis = t.x < t.y ? t.x < t.z ? 0 : 3 : t.y < t.z ? 2 : 3;
    }

    uint3 coord;
    float3 t;
    uint3 ustep;
    float3 delta;

    {
        // For complicated reasons I don't fully understand we'll want to use the sign of the inverse as well.
        int3 sign_direction = sign(inverse_direction);

        // Initalize voxel traversal.
        coord = uint3(clamp(floor(ray_position), 0, _MainTex_TexelSize.z - 1));
        t = (coord + 0.5 * (1 + sign_direction) - ray_position) * inverse_direction;

        ustep = uint3(sign_direction);
        delta = inverse_direction * sign_direction;
    }
    
    // RUN OUR MAIN TRAVERSAL LOOP HERE
    [loop]
    while (true)
    {
        if(any(coord > uint(_MainTex_TexelSize.z) - 1u)) return false;

        // Retrieve our bitmask
        uint2 bitmask = asuint(_MainTex.Load(uint4(coord, 0)));

        // If x or y are anything other than 0, there are voxels here.
        // We need to step into the brick and traverse through it.
        // Otherwise we can skip the entire brick.
        if (bitmask.x || bitmask.y)
        {
            // Extract our hit location here.
            // This is the dirty method that I really don't like but it works.
            // Sort of...
            float t_inside = dot(t, mask) - dot(delta, mask);

            // Notice the CRIMES: We push the ray into the cube a tiny little amount to compensate for floating point imprecision.
            // 10-05-26 HAHA FIXED!
            //float3 hit = (ray_position + direction * t_inside + direction * 0.0001) * 4;

            hit_position = (ray_position + direction * t_inside) * 4;

            // We know the voxel has to be within the brick so we can clamp to the maximum and minimum brick coordinates.
            hit_coord = uint3(clamp(floor(hit_position), coord << 2, (coord << 2) + 3));
            float3 t0 = (hit_coord + 0.5 * (1 + sign(inverse_direction)) - hit_position) * inverse_direction;

            [loop]
            while(!(any((hit_coord >> 2) != coord)))
            {
                // Compute our bitmask offset and extract the bit.
                uint n = encode(hit_coord & 3);
                //uint bit = (n < 32) ? (bitmask.x & (1u << n)) : (bitmask.y & (1u << (n - 32)));
                //uint bit = bitmask[n >> 5] & (1u << (n & 31));

                // If the bit is anything other than 0 we've hit a voxel.
                if((n < 32) ? (bitmask.x & (1u << n)) : (bitmask.y & (1u << (n - 32))))
                {
                    t_inside += (dot(t0, mask) - dot(delta, mask)) * 0.25;

                    hit_position = (ray_position + direction * t_inside) * _MainTex_TexelSize.x;

                    return true;
                }

                mask = t0.x < t0.y ? t0.x < t0.z ? uint3(1, 0, 0) : uint3(0, 0, 1) : t0.y < t0.z ? uint3(0, 1, 0) : uint3(0, 0, 1);
                hit_coord += ustep * mask;
                t0 += delta * mask;
            }
        }
        
        mask = t.x < t.y ? t.x < t.z ? uint3(1, 0, 0) : uint3(0, 0, 1) : t.y < t.z ? uint3(0, 1, 0) : uint3(0, 0, 1);
        coord += ustep * mask;
        t += delta * mask;
    }
    // If we get to here something has gone wrong and we should discard this ray. Or not...
    return false;
}