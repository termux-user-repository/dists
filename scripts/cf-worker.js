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
      const packageArray = packageDebNameModified.split("_");
      const packageName = packageArray.at(0);
      const packageVersion = packageArray.at(1);
      // Try packages from tur-dists
      let url = `https://github.com/tur-dists/${packageName}/releases/download/${packageVersion}/${packageDebNameModified}`;
      let response = await fetch(url, { method: "HEAD" });
      if (response.ok) {
        return Response.redirect(url, 302);
      }
      // Try the new package_name tag
      url = `https://github.com/termux-user-repository/dists/releases/download/${packageName}/${packageDebNameModified}`;
      response = await fetch(url, { method: "HEAD" });
      if (response.ok) {
        return Response.redirect(url, 302);
      }
      // Fallback to legacy 0.1 tag
      return Response.redirect(fallbackUrl, 302);
    } catch (err) {
      // Fallback to legacy 0.1 tag
      return Response.redirect(fallbackUrl, 302);
    }
  }

  return Response.redirect("https://github.com/termux-user-repository/tur", 302);
}
