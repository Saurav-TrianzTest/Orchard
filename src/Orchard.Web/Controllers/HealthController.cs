using System;
using System.Web.Mvc;

namespace Orchard.Web.Controllers
{
    /// <summary>
    /// Simple health check endpoint for container orchestration platforms (e.g., Kubernetes on AWS EKS).
    /// Returns HTTP 200 with a JSON status when the application is running.
    /// </summary>
    public class HealthController : Controller
    {
        [HttpGet]
        [AllowAnonymous]
        public ActionResult Index()
        {
            return Json(new
            {
                status = "healthy",
                timestamp = DateTime.UtcNow
            }, JsonRequestBehavior.AllowGet);
        }
    }
}
