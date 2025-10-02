export default {
  async fetch(request, env) {
    return await handleRequest(request).catch(
      (err) => new Response(err.stack, { status: 500 })
    )
  }
}

/**
 * Many more examples available at:
 *   https://developers.cloudflare.com/workers/examples
 * @param {Request} request
 * @returns {Promise<Response>}
 */
async function handleRequest(request) {
  const { pathname } = new URL(request.url);
  const pathArray = pathname.split("/");

  if (pathname.startsWith("/dists")) {
    return fetch("https://termux-user-repository.github.io/dists" + pathname);
  }

  if (pathname.startsWith("/pool")) {
    const packageDebName = pathArray.at(-1);
    const packageDebNameModified = packageDebName.replaceAll(/[^a-zA-Z0-9-_+%]+/g, ".");
    const fallbackUrl = "https://github.com/termux-user-repository/dists/releases/download/0.1/" + packageDebNameModified;
    try {
      // Try the new package_name tag
      const packageName = packageDebName.split("_").at(0);
      const primaryUrl = "https://github.com/termux-user-repository/dists/releases/download/" + packageName + "/" + packageDebNameModified;
      const response = await fetch(primaryUrl, { method: "HEAD" });
      if (response.ok) {
        return Response.redirect(primaryUrl, 302);
      } else {
        // Fallback to legacy 0.1 tag
        return Response.redirect(fallbackUrl, 302);
      }
    } catch (err) {
      // Fallback to legacy 0.1 tag
      return Response.redirect(fallbackUrl, 302);
    }
  }

  return Response.redirect("https://github.com/termux-user-repository/tur", 302);
}
