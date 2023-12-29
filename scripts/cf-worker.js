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
    const packageName = pathArray.at(-1);
    const packageNameModified = packageName.replaceAll(/[^a-zA-Z0-9-_+]+/g, ".");
    return Response.redirect(
      "https://github.com/termux-user-repository/dists/releases/download/0.1/" + packageNameModified, 302);
  }

  return Response.redirect("https://github.com/termux-user-repository/tur", 302);
}
