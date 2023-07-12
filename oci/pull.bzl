"""A repository rule to pull image layers using Bazel's downloader.

Typical usage in `WORKSPACE.bazel`:

```starlark
load("@rules_oci//oci:pull.bzl", "oci_pull")

# A single-arch base image
oci_pull(
    name = "distroless_java",
    digest = "sha256:161a1d97d592b3f1919801578c3a47c8e932071168a96267698f4b669c24c76d",
    image = "gcr.io/distroless/java17",
)

# A multi-arch base image
oci_pull(
    name = "distroless_static",
    digest = "sha256:c3c3d0230d487c0ad3a0d87ad03ee02ea2ff0b3dcce91ca06a1019e07de05f12",
    image = "gcr.io/distroless/static",
    platforms = [
        "linux/amd64",
        "linux/arm64",
    ],
)
```

Now you can refer to these as a base layer in `BUILD.bazel`.
The target is named the same as the external repo, so you can use a short label syntax:

```
oci_image(
    name = "app",
    base = "@distroless_static",
    ...
)
```
"""

load("//oci/private:pull.bzl", "oci_alias", _oci_pull = "oci_pull")
load("//oci/private:util.bzl", "util")

# Note: there is no exhaustive list, image authors can use whatever name they like.
# This is only used for the oci_alias rule that makes a select() - if a mapping is missing,
# users can just write their own select() for it.
_PLATFORM_TO_BAZEL_CPU = {
    "linux/amd64": "@platforms//cpu:x86_64",
    "linux/arm64": "@platforms//cpu:arm64",
    "linux/arm64/v8": "@platforms//cpu:arm64",
    "linux/arm/v7": "@platforms//cpu:armv7",
    "linux/ppc64le": "@platforms//cpu:ppc",
    "linux/s390x": "@platforms//cpu:s390x",
    "linux/386": "@platforms//cpu:i386",
    "linux/mips64le": "@platforms//cpu:mips64",
}

def oci_pull(name, image = None, repository = None, registry = None, platforms = None, digest = None, tag = None, reproducible = True):
    """Repository macro to fetch image manifest data from a remote docker registry.

    To use the resulting image, you can use the `@wkspc` shorthand label, for example
    if `name = "distroless_base"`, then you can just use `base = "@distroless_base"`
    in rules like `oci_image`.

    > This shorthand syntax is broken on the command-line prior to Bazel 6.2.
    > See https://github.com/bazelbuild/bazel/issues/4385

    Args:
        name: repository with this name is created
        image: the remote image, such as `gcr.io/bazel-public/bazel`.
            A tag can be suffixed with a colon, like `debian:latest`,
            and a digest can be suffixed with an at-sign, like
            `debian@sha256:e822570981e13a6ef1efcf31870726fbd62e72d9abfdcf405a9d8f566e8d7028`.

            Exactly one of image or {registry,repository} should be set.
        registry: the remote registry domain, such as `gcr.io` or `docker.io`.
            When set, repository must be set as well.
        repository: the image path beneath the registry, such as `distroless/static`.
            When set, registry must be set as well.
        platforms: for multi-architecture images, a dictionary of the platforms it supports
            This creates a separate external repository for each platform, avoiding fetching layers.
        digest: the digest string, starting with "sha256:", "sha512:", etc.
            If omitted, instructions for pinning are provided.
        tag: a tag to choose an image from the registry.
            Exactly one of `tag` and `digest` must be set.
            Since tags are mutable, this is not reproducible, so a warning is printed.
        reproducible: Set to False to silence the warning about reproducibility when using `tag`.
    """

    # Check syntax sugar for registry/repository in place of image
    if (repository and not registry) or (registry and not repository):
        fail("When one of repository or registry is set, the other must be as well")
    if image and (repository or registry):
        fail("Only one of 'image' or '{registry, repository}' may be set")
    if not image and not (repository or registry):
        fail("One of 'image' or '{registry, repository}' must be set")

    if image:
        scheme, registry, repository, maybe_digest, maybe_tag = util.parse_image(image)
        if maybe_digest:
            digest = maybe_digest
        if maybe_tag:
            tag = maybe_tag
    else:
        scheme = None

    if reproducible and digest and tag:
        # Users might wish to leave tag=latest as "documentation" however if we just ignore tag
        # then it's never checked which means the documentation can be wrong.
        # For now just forbit having both, it's a non-breaking change to allow it later.
        fail("Only one of 'digest' or 'tag' may be set")
    if not digest and not tag:
        fail("One of 'digest' or 'tag' must be set")

    platform_to_image = None
    single_platform = None

    if platforms:
        platform_to_image = {}
        for plat in platforms:
            plat_name = "_".join([name] + plat.split("/"))
            _oci_pull(
                name = plat_name,
                scheme = scheme,
                registry = registry,
                repository = repository,
                identifier = digest or tag,
                platform = plat,
                target_name = plat_name,
            )
            if plat in _PLATFORM_TO_BAZEL_CPU:
                platform_to_image[_PLATFORM_TO_BAZEL_CPU[plat]] = "@" + plat_name
    else:
        single_platform = "{}_single".format(name)
        _oci_pull(
            name = single_platform,
            scheme = scheme,
            registry = registry,
            repository = repository,
            identifier = digest or tag,
            target_name = single_platform,
        )

    oci_alias(
        name = name,
        target_name = name,
        # image attributes
        scheme = scheme,
        registry = registry,
        repository = repository,
        identifier = digest or tag,
        # image attributes
        platforms = platform_to_image,
        platform = single_platform,
    )
