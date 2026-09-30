-- 仅授权删除已确认未被新关系表引用的旧测试图片，不扩大到其他媒体。
create policy triptrail_remove_old_test_fixture on storage.objects
for delete to anon, authenticated
using (
  bucket_id = 'triptrail-media'
  and name = '00000000-0000-4000-8000-000000000002/02361b65063679d9d2dda1eedbfa49f1f345d22f12201bc6367b79d7c5443f22.jpg'
);
